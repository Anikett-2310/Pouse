use std::collections::VecDeque;
use std::ptr::null_mut;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::{Duration, Instant};

use windows::core::{Interface, Result, GUID, HRESULT};
use windows::Win32::Graphics::Direct3D::*;
use windows::Win32::Graphics::Direct3D11::*;
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::*;

use crate::remote_screen::annexb::{AnnexBProcessor, MAX_ACCESS_UNIT_SIZE};
use crate::remote_screen::video_processor::GpuVideoProcessor;
use crate::remote_screen::EncodeMetrics;

// CODECAPI_AVEncVideoForceKeyFrame GUID: {3950F844-9B7E-49E8-A4A3-ACAE7064A1D6}
pub const CODECAPI_AVENC_VIDEO_FORCE_KEY_FRAME_GUID: GUID = GUID::from_values(
    0x3950f844,
    0x9b7e,
    0x49e8,
    [0xa4, 0xa3, 0xac, 0xae, 0x70, 0x64, 0xa1, 0xd6],
);

pub const CODECAPI_AVLOW_LATENCY_MODE_GUID: GUID = GUID::from_values(
    0x9c270cd3,
    0x20e8,
    0x4243,
    [0xbc, 0xde, 0x4b, 0x65, 0xa9, 0x80, 0x82, 0x53],
);

pub const CODECAPI_AVENC_MPV_DEFAULT_BPICTURE_COUNT_GUID: GUID = GUID::from_values(
    0x8d390a4d,
    0x620e,
    0x4360,
    [0xa2, 0xda, 0x57, 0x0b, 0x77, 0x7a, 0x83, 0xd4],
);

#[derive(Clone)]
pub struct SendRaw<T>(pub T);
unsafe impl<T> Send for SendRaw<T> {}
unsafe impl<T> Sync for SendRaw<T> {}

impl SendRaw<IMFMediaEventGenerator> {
    pub fn get_event(&self) -> Result<IMFMediaEvent> {
        unsafe { self.0.GetEvent(MF_EVENT_FLAG_NONE) }
    }
}

pub enum EncoderCommand {
    EncodeFrame {
        texture: ID3D11Texture2D,
        timestamp_qpc_100ns: i64,
        frame_number: u64,
    },
    ForceKeyframe,
    Shutdown,
}

pub enum EncoderResponse {
    InitSuccess {
        mft_name: String,
        is_hardware: bool,
        zero_copy_verified: bool,
        same_device: bool,
    },
    InitError(String),
    EncodedSample {
        data: Vec<u8>,
        metrics: EncodeMetrics,
    },
    KeyframeForcedAck,
    Error(String),
    ShutdownAck,
}

pub struct MediaFoundationEncoder {
    cmd_tx: Sender<EncoderCommand>,
    resp_rx: std::sync::Mutex<Receiver<EncoderResponse>>,
    is_hardware: bool,
    mft_name: String,
    zero_copy_verified: bool,
    same_device: bool,
}

impl MediaFoundationEncoder {
    pub fn start(
        d3d_device: ID3D11Device,
        d3d_context: ID3D11DeviceContext,
        width: u32,
        height: u32,
        force_cpu_baseline: bool,
    ) -> Result<Self> {
        let (cmd_tx, cmd_rx) = channel::<EncoderCommand>();
        let (resp_tx, resp_rx) = channel::<EncoderResponse>();

        thread::spawn(move || {
            encoder_thread_proc(
                d3d_device,
                d3d_context,
                width,
                height,
                force_cpu_baseline,
                cmd_rx,
                resp_tx,
            );
        });

        match resp_rx.recv() {
            Ok(EncoderResponse::InitSuccess {
                mft_name,
                is_hardware,
                zero_copy_verified,
                same_device,
            }) => Ok(Self {
                cmd_tx,
                resp_rx: std::sync::Mutex::new(resp_rx),
                is_hardware,
                mft_name,
                zero_copy_verified,
                same_device,
            }),
            Ok(EncoderResponse::InitError(err)) => Err(windows::core::Error::new(HRESULT(-1), err)),
            _ => Err(windows::core::Error::new(
                HRESULT(-1),
                "Failed to receive encoder init response",
            )),
        }
    }

    pub fn encode_frame(&self, texture: ID3D11Texture2D, timestamp_qpc_100ns: i64, frame_number: u64) -> Result<()> {
        self.cmd_tx
            .send(EncoderCommand::EncodeFrame {
                texture,
                timestamp_qpc_100ns,
                frame_number,
            })
            .map_err(|e| windows::core::Error::new(HRESULT(-1), e.to_string()))
    }

    pub fn force_keyframe(&self) -> Result<()> {
        self.cmd_tx
            .send(EncoderCommand::ForceKeyframe)
            .map_err(|e| windows::core::Error::new(HRESULT(-1), e.to_string()))
    }

    pub fn try_recv_response(&self) -> Option<EncoderResponse> {
        self.resp_rx.lock().ok()?.try_recv().ok()
    }

    pub fn is_hardware(&self) -> bool {
        self.is_hardware
    }

    pub fn mft_name(&self) -> &str {
        &self.mft_name
    }

    pub fn zero_copy_verified(&self) -> bool {
        self.zero_copy_verified
    }

    pub fn same_device(&self) -> bool {
        self.same_device
    }

    pub fn shutdown_and_drain(self) -> Vec<EncoderResponse> {
        let mut responses = Vec::new();
        if self.cmd_tx.send(EncoderCommand::Shutdown).is_ok() {
            while let Ok(resp) = self.resp_rx.lock().unwrap().recv() {
                if matches!(resp, EncoderResponse::ShutdownAck) {
                    break;
                }
                responses.push(resp);
            }
        }
        responses
    }
}

fn encoder_thread_proc(
    d3d_device: ID3D11Device,
    d3d_context: ID3D11DeviceContext,
    width: u32,
    height: u32,
    force_cpu_baseline: bool,
    cmd_rx: Receiver<EncoderCommand>,
    resp_tx: Sender<EncoderResponse>,
) {
    unsafe {
        if CoInitializeEx(None, COINIT_MULTITHREADED).is_err() {
            let _ = resp_tx.send(EncoderResponse::InitError("CoInitializeEx failed".to_string()));
            return;
        }

        if let Err(e) = MFStartup(MF_VERSION, MFSTARTUP_FULL) {
            let _ = resp_tx.send(EncoderResponse::InitError(format!("MFStartup failed: {:?}", e)));
            CoUninitialize();
            return;
        }
    }

    // Create DXGI Device Manager for hardware MFT device sharing
    let mut reset_token: u32 = 0;
    let mut dxgi_mgr_opt: Option<IMFDXGIDeviceManager> = None;
    if let Err(e) = unsafe { MFCreateDXGIDeviceManager(&mut reset_token, &mut dxgi_mgr_opt) } {
        let _ = resp_tx.send(EncoderResponse::InitError(format!("MFCreateDXGIDeviceManager failed: {:?}", e)));
        unsafe {
            let _ = MFShutdown();
            CoUninitialize();
        }
        return;
    }
    let dxgi_mgr = dxgi_mgr_opt.unwrap();

    if let Err(e) = unsafe { dxgi_mgr.ResetDevice(&d3d_device, reset_token) } {
        let _ = resp_tx.send(EncoderResponse::InitError(format!("dxgi_mgr.ResetDevice failed: {:?}", e)));
        unsafe {
            let _ = MFShutdown();
            CoUninitialize();
        }
        return;
    }

    let mut is_hardware = false;
    let mut is_async_mft = false;
    let mut mft_name = String::new();
    let mut transform: Option<IMFTransform> = None;

    // 1. Enumerate Hardware MFT first
    if !force_cpu_baseline {
        if let Ok(mfts) = enumerate_h264_encoders(true) {
            for (name, clsid, mft) in mfts {
                // Unlock ASYNC attribute FIRST
                if let Ok(attributes) = unsafe { mft.GetAttributes() } {
                    let _ = unsafe { attributes.SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1) };
                }

                // Check D3D manager
                let param = dxgi_mgr.as_raw() as usize;
                let res = unsafe { mft.ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, param) };
                if res.is_err() {
                    println!("[ENCODER DIAGNOSTIC] HW MFT '{}' ({:?}) rejected SET_D3D_MANAGER: {:?}", name, clsid, res);
                    continue;
                }

                if configure_encoder_media_types(&mft, width, height).is_ok() {
                    let is_async = unsafe { mft.GetAttributes().and_then(|attr| attr.GetUINT32(&MF_TRANSFORM_ASYNC)) }.unwrap_or(0);
                    is_async_mft = is_async == 1 || mft.cast::<IMFMediaEventGenerator>().is_ok();
                    transform = Some(mft);
                    mft_name = format!("{} ({:?})", name, clsid);
                    is_hardware = true;
                    println!("[ENCODER STARTUP SELECTION] HARDWARE ENCODER ACTIVE: {} (Async={})", mft_name, is_async_mft);
                    break;
                }
            }
        }
    }

    // 2. Software Fallback at startup if HW unavailable or rejected
    if transform.is_none() {
        println!("[ENCODER STARTUP SELECTION] HARDWARE MFT UNSUPPORTED/UNAVAILABLE -> SOFTWARE ENCODER ACTIVE");
        if let Ok(mfts) = enumerate_h264_encoders(false) {
            for (name, clsid, mft) in mfts {
                if let Ok(attributes) = unsafe { mft.GetAttributes() } {
                    let _ = unsafe { attributes.SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1) };
                }
                let _ = configure_encoder_media_types(&mft, width, height);
                transform = Some(mft);
                mft_name = format!("{} ({:?})", name, clsid);
                is_hardware = false;
                is_async_mft = false;
                println!("[ENCODER SW SELECTED] Selected software fallback MFT: {}", mft_name);
                break;
            }
        }
    }

    let transform = match transform {
        Some(t) => t,
        None => {
            let _ = resp_tx.send(EncoderResponse::InitError("No H.264 MFT encoder found".to_string()));
            unsafe {
                let _ = MFShutdown();
                CoUninitialize();
            }
            return;
        }
    };

    // Configure Low-Latency & Zero-B-frame mode on ICodecAPI if supported
    if let Ok(codec_api) = transform.cast::<ICodecAPI>() {
        let low_latency_var = windows::core::VARIANT::from(true);
        let res_ll = unsafe { codec_api.SetValue(&CODECAPI_AVLOW_LATENCY_MODE_GUID, &low_latency_var) };
        println!("[ENCODER LOW-LATENCY] Set CODECAPI_AVLowLatencyMode: {:?}", res_ll);

        let zero_b_var = windows::core::VARIANT::from(0u32);
        let res_b = unsafe { codec_api.SetValue(&CODECAPI_AVENC_MPV_DEFAULT_BPICTURE_COUNT_GUID, &zero_b_var) };
        println!("[ENCODER LOW-LATENCY] Set CODECAPI_AVEncMPVDefaultBPictureCount(0): {:?}", res_b);
    }

    // Set up Video Processor for GPU BGRA -> NV12 conversion
    let gpu_processor = GpuVideoProcessor::new(&d3d_device, &d3d_context, width, height).ok();
    let zero_copy_verified = !force_cpu_baseline && is_hardware && gpu_processor.is_some();
    let same_device = true;

    if is_async_mft {
        run_async_encoder_loop(
            transform,
            d3d_device,
            d3d_context,
            gpu_processor,
            width,
            height,
            mft_name,
            is_hardware,
            zero_copy_verified,
            same_device,
            cmd_rx,
            resp_tx,
        );
    } else {
        run_sync_encoder_loop(
            transform,
            d3d_device,
            d3d_context,
            gpu_processor,
            width,
            height,
            mft_name,
            is_hardware,
            zero_copy_verified,
            same_device,
            cmd_rx,
            resp_tx,
        );
    }

    unsafe {
        let _ = MFShutdown();
        CoUninitialize();
    }
}

fn run_async_encoder_loop(
    transform: IMFTransform,
    d3d_device: ID3D11Device,
    d3d_context: ID3D11DeviceContext,
    gpu_processor: Option<GpuVideoProcessor>,
    width: u32,
    height: u32,
    mft_name: String,
    is_hardware: bool,
    zero_copy_verified: bool,
    same_device: bool,
    cmd_rx: Receiver<EncoderCommand>,
    resp_tx: Sender<EncoderResponse>,
) {
    let event_gen: IMFMediaEventGenerator = match transform.cast() {
        Ok(eg) => eg,
        Err(e) => {
            let _ = resp_tx.send(EncoderResponse::InitError(format!("Async MFT missing IMFMediaEventGenerator: {:?}", e)));
            return;
        }
    };

    let stream_info = match unsafe { transform.GetOutputStreamInfo(0) } {
        Ok(si) => si,
        Err(e) => {
            let _ = resp_tx.send(EncoderResponse::InitError(format!("GetOutputStreamInfo failed: {:?}", e)));
            return;
        }
    };
    let provides_samples = (stream_info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 as u32 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0 as u32)) != 0;

    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0) };
    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0) };
    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0) };

    // Spawn dedicated event reader thread
    let (event_tx, event_rx) = channel::<SendRaw<IMFMediaEvent>>();
    let event_gen_clone = SendRaw(event_gen.clone());

    thread::spawn(move || {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
        loop {
            match event_gen_clone.get_event() {
                Ok(ev) => {
                    let ev_type = unsafe { ev.GetType().unwrap_or(0) };
                    let is_drain_complete = ev_type == METransformDrainComplete.0 as u32;
                    if event_tx.send(SendRaw(ev)).is_err() || is_drain_complete {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        unsafe { CoUninitialize(); }
    });

    let mut annexb = AnnexBProcessor::new();
    if let Ok(out_type) = unsafe { transform.GetOutputCurrentType(0) } {
        let mut blob_ptr = null_mut();
        let mut blob_size = 0;
        if unsafe { out_type.GetAllocatedBlob(&MF_MT_MPEG_SEQUENCE_HEADER, &mut blob_ptr, &mut blob_size) }.is_ok() {
            let slice = unsafe { std::slice::from_raw_parts(blob_ptr, blob_size as usize) };
            annexb.set_extra_data(slice);
            unsafe { CoTaskMemFree(Some(blob_ptr as _)) };
        }
    }

    let _ = resp_tx.send(EncoderResponse::InitSuccess {
        mft_name: mft_name.clone(),
        is_hardware,
        zero_copy_verified,
        same_device,
    });

    let mut pending_inputs: VecDeque<(IMFSample, u64, i64, Instant)> = VecDeque::new();
    let mut in_flight: VecDeque<(u64, i64, Instant)> = VecDeque::new();
    let mut needed_inputs: usize = 0;
    let mut force_next_keyframe = false;

    loop {
        // 1. Drain pending MFT events
        while let Ok(SendRaw(ev)) = event_rx.try_recv() {
            let ev_type = unsafe { ev.GetType().unwrap_or(0) };

            if ev_type == METransformNeedInput.0 as u32 {
                needed_inputs += 1;
            } else if ev_type == METransformHaveOutput.0 as u32 {
                let sample_out: Option<IMFSample> = if provides_samples { None } else { unsafe { MFCreateSample().ok() } };
                let output_buffer = MFT_OUTPUT_DATA_BUFFER {
                    dwStreamID: 0,
                    pSample: std::mem::ManuallyDrop::new(sample_out),
                    dwStatus: 0,
                    pEvents: std::mem::ManuallyDrop::new(None),
                };
                let mut out_status = 0;
                let mut buffers = [output_buffer];
                if unsafe { transform.ProcessOutput(0, &mut buffers, &mut out_status) }.is_ok() {
                    if let Some(sample) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                        let sample_time_100ns = unsafe { sample.GetSampleTime() }.unwrap_or(0);
                        let (frame_number, timestamp_qpc, submit_start) = in_flight.pop_front().unwrap_or((0, 0, Instant::now()));
                        let dispatch_overhead_us = submit_start.elapsed().as_micros() as u64;

                        if let Ok(buf) = unsafe { sample.ConvertToContiguousBuffer() } {
                            let mut ptr = null_mut();
                            let mut max_len = 0;
                            let mut cur_len = 0;
                            if unsafe { buf.Lock(&mut ptr, Some(&mut max_len), Some(&mut cur_len)) }.is_ok() && cur_len > 0 {
                                let raw_slice = unsafe { std::slice::from_raw_parts(ptr, cur_len as usize) };
                                match annexb.process_sample(raw_slice) {
                                    Ok((annexb_bytes, is_keyframe)) => {
                                        let metrics = EncodeMetrics {
                                            frame_number,
                                            encode_duration_us: dispatch_overhead_us,
                                            sample_size_bytes: annexb_bytes.len(),
                                            is_keyframe,
                                            timestamp_qpc,
                                            output_sample_time_100ns: sample_time_100ns,
                                        };
                                        let _ = resp_tx.send(EncoderResponse::EncodedSample {
                                            data: annexb_bytes,
                                            metrics,
                                        });
                                    }
                                    Err(err) => {
                                        println!("[ASYNC ENCODER SAFETY] Sample dropped: {}", err);
                                        force_next_keyframe = true;
                                    }
                                }
                                let _ = unsafe { buf.Unlock() };
                            }
                        }
                    }
                }
            }
        }

        // 2. Submit pending input samples to MFT if MFT requested input
        while needed_inputs > 0 && !pending_inputs.is_empty() {
            let (input_sample, f_num, qpc_ts, _) = pending_inputs.pop_front().unwrap();
            let submit_start = Instant::now();
            if let Err(e) = unsafe { transform.ProcessInput(0, &input_sample, 0) } {
                println!("[ASYNC ENCODER ERROR] ProcessInput error: {:?}", e);
            } else {
                in_flight.push_back((f_num, qpc_ts, submit_start));
            }
            needed_inputs -= 1;
        }

        // 3. Receive next command with 1ms timeout
        let cmd = match cmd_rx.recv_timeout(Duration::from_millis(1)) {
            Ok(c) => c,
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
        };

        match cmd {
            EncoderCommand::EncodeFrame {
                texture,
                timestamp_qpc_100ns,
                frame_number,
            } => {
                let start_time = Instant::now();
                if force_next_keyframe {
                    if let Ok(codec_api) = transform.cast::<ICodecAPI>() {
                        let var = windows::core::VARIANT::from(true);
                        unsafe {
                            let _ = codec_api.SetValue(&CODECAPI_AVENC_VIDEO_FORCE_KEY_FRAME_GUID, &var);
                        }
                    }
                    force_next_keyframe = false;
                }

                let input_sample = if let Some(ref gpu_proc) = gpu_processor {
                    if let Ok(nv12_tex) = gpu_proc.convert_bgra_to_nv12(&texture) {
                        create_dxgi_sample(&nv12_tex, timestamp_qpc_100ns).ok()
                    } else {
                        None
                    }
                } else {
                    create_cpu_sample(&d3d_device, &d3d_context, &texture, width, height, timestamp_qpc_100ns).ok()
                };

                let input_sample = match input_sample {
                    Some(s) => s,
                    None => {
                        let _ = resp_tx.send(EncoderResponse::Error("Failed to create input sample".to_string()));
                        continue;
                    }
                };

                pending_inputs.push_back((input_sample, frame_number, timestamp_qpc_100ns, start_time));
            }
            EncoderCommand::ForceKeyframe => {
                force_next_keyframe = true;
                let _ = resp_tx.send(EncoderResponse::KeyframeForcedAck);
            }
            EncoderCommand::Shutdown => {
                let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0) };
                let mut drained_count = 0;

                while let Ok(SendRaw(ev)) = event_rx.recv() {
                    let ev_type = unsafe { ev.GetType().unwrap_or(0) };

                    if ev_type == METransformHaveOutput.0 as u32 {
                        let sample_out: Option<IMFSample> = if provides_samples { None } else { unsafe { MFCreateSample().ok() } };
                        let output_buffer = MFT_OUTPUT_DATA_BUFFER {
                            dwStreamID: 0,
                            pSample: std::mem::ManuallyDrop::new(sample_out),
                            dwStatus: 0,
                            pEvents: std::mem::ManuallyDrop::new(None),
                        };
                        let mut out_status = 0;
                        let mut buffers = [output_buffer];
                        if unsafe { transform.ProcessOutput(0, &mut buffers, &mut out_status) }.is_ok() {
                            if let Some(sample) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                                let sample_time_100ns = unsafe { sample.GetSampleTime() }.unwrap_or(0);
                                let (frame_number, timestamp_qpc, _) = in_flight.pop_front().unwrap_or((999999, 0, Instant::now()));
                                if let Ok(buf) = unsafe { sample.ConvertToContiguousBuffer() } {
                                    let mut ptr = null_mut();
                                    let mut max_len = 0;
                                    let mut cur_len = 0;
                                    if unsafe { buf.Lock(&mut ptr, Some(&mut max_len), Some(&mut cur_len)) }.is_ok() && cur_len > 0 {
                                        let raw_slice = unsafe { std::slice::from_raw_parts(ptr, cur_len as usize) };
                                        if let Ok((annexb_bytes, is_keyframe)) = annexb.process_sample(raw_slice) {
                                            drained_count += 1;
                                            let metrics = EncodeMetrics {
                                                frame_number,
                                                encode_duration_us: 0,
                                                sample_size_bytes: annexb_bytes.len(),
                                                is_keyframe,
                                                timestamp_qpc,
                                                output_sample_time_100ns: sample_time_100ns,
                                            };
                                            let _ = resp_tx.send(EncoderResponse::EncodedSample {
                                                data: annexb_bytes,
                                                metrics,
                                            });
                                        }
                                        let _ = unsafe { buf.Unlock() };
                                    }
                                }
                            }
                        }
                    } else if ev_type == METransformDrainComplete.0 as u32 {
                        break;
                    }
                }

                println!("[ASYNC ENCODER SHUTDOWN] Recovered {} buffered frames on drain.", drained_count);
                let _ = resp_tx.send(EncoderResponse::ShutdownAck);
                break;
            }
        }
    }
}

fn run_sync_encoder_loop(
    transform: IMFTransform,
    d3d_device: ID3D11Device,
    d3d_context: ID3D11DeviceContext,
    gpu_processor: Option<GpuVideoProcessor>,
    width: u32,
    height: u32,
    mft_name: String,
    is_hardware: bool,
    zero_copy_verified: bool,
    same_device: bool,
    cmd_rx: Receiver<EncoderCommand>,
    resp_tx: Sender<EncoderResponse>,
) {
    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0) };
    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0) };
    let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0) };

    let mut annexb = AnnexBProcessor::new();
    if let Ok(out_type) = unsafe { transform.GetOutputCurrentType(0) } {
        let mut blob_ptr = null_mut();
        let mut blob_size = 0;
        if unsafe { out_type.GetAllocatedBlob(&MF_MT_MPEG_SEQUENCE_HEADER, &mut blob_ptr, &mut blob_size) }.is_ok() {
            let slice = unsafe { std::slice::from_raw_parts(blob_ptr, blob_size as usize) };
            annexb.set_extra_data(slice);
            unsafe { CoTaskMemFree(Some(blob_ptr as _)) };
        }
    }

    let _ = resp_tx.send(EncoderResponse::InitSuccess {
        mft_name: mft_name.clone(),
        is_hardware,
        zero_copy_verified,
        same_device,
    });

    let mut force_next_keyframe = false;

    while let Ok(cmd) = cmd_rx.recv() {
        match cmd {
            EncoderCommand::EncodeFrame {
                texture,
                timestamp_qpc_100ns,
                frame_number,
            } => {
                let start_time = Instant::now();

                if force_next_keyframe {
                    if let Ok(codec_api) = transform.cast::<ICodecAPI>() {
                        let var = windows::core::VARIANT::from(true);
                        unsafe {
                            let _ = codec_api.SetValue(&CODECAPI_AVENC_VIDEO_FORCE_KEY_FRAME_GUID, &var);
                        }
                    }
                    force_next_keyframe = false;
                }

                let input_sample = if let Some(ref gpu_proc) = gpu_processor {
                    if let Ok(nv12_tex) = gpu_proc.convert_bgra_to_nv12(&texture) {
                        create_dxgi_sample(&nv12_tex, timestamp_qpc_100ns).ok()
                    } else {
                        None
                    }
                } else {
                    create_cpu_sample(&d3d_device, &d3d_context, &texture, width, height, timestamp_qpc_100ns).ok()
                };

                let input_sample = match input_sample {
                    Some(s) => s,
                    None => {
                        let _ = resp_tx.send(EncoderResponse::Error("Failed to create input sample".to_string()));
                        continue;
                    }
                };

                if let Err(e) = unsafe { transform.ProcessInput(0, &input_sample, 0) } {
                    println!("[SYNC ENCODER ERROR] ProcessInput error: {:?}", e);
                    let _ = resp_tx.send(EncoderResponse::Error(format!("ProcessInput failed: {:?}", e)));
                    continue;
                }

                loop {
                    let sample_out: Option<IMFSample> = unsafe { MFCreateSample().ok() };
                    if let Ok(media_buf) = unsafe { MFCreateMemoryBuffer(MAX_ACCESS_UNIT_SIZE as u32) } {
                        if let Some(sb) = sample_out.as_ref() {
                            let _ = unsafe { sb.AddBuffer(&media_buf) };
                        }
                    }

                    let output_buffer = MFT_OUTPUT_DATA_BUFFER {
                        dwStreamID: 0,
                        pSample: std::mem::ManuallyDrop::new(sample_out),
                        dwStatus: 0,
                        pEvents: std::mem::ManuallyDrop::new(None),
                    };

                    let mut status = 0;
                    let mut buffers = [output_buffer];
                    let res = unsafe { transform.ProcessOutput(0, &mut buffers, &mut status) };

                    match res {
                        Ok(()) => {
                            if let Some(sample) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                                let sample_time_100ns = unsafe { sample.GetSampleTime() }.unwrap_or(0);
                                if let Ok(buf) = unsafe { sample.ConvertToContiguousBuffer() } {
                                    let mut ptr = null_mut();
                                    let mut max_len = 0;
                                    let mut cur_len = 0;
                                    if unsafe { buf.Lock(&mut ptr, Some(&mut max_len), Some(&mut cur_len)) }.is_ok() && cur_len > 0 {
                                        let raw_slice = unsafe { std::slice::from_raw_parts(ptr, cur_len as usize) };
                                        match annexb.process_sample(raw_slice) {
                                            Ok((annexb_bytes, is_keyframe)) => {
                                                let duration_us = start_time.elapsed().as_micros() as u64;
                                                let metrics = EncodeMetrics {
                                                    frame_number,
                                                    encode_duration_us: duration_us,
                                                    sample_size_bytes: annexb_bytes.len(),
                                                    is_keyframe,
                                                    timestamp_qpc: timestamp_qpc_100ns,
                                                    output_sample_time_100ns: sample_time_100ns,
                                                };
                                                let _ = resp_tx.send(EncoderResponse::EncodedSample {
                                                    data: annexb_bytes,
                                                    metrics,
                                                });
                                            }
                                            Err(err) => {
                                                println!("[SYNC ENCODER SAFETY] Sample dropped: {}", err);
                                                force_next_keyframe = true;
                                            }
                                        }
                                        let _ = unsafe { buf.Unlock() };
                                    }
                                }
                            }
                        }
                        Err(e) if e.code() == MF_E_TRANSFORM_NEED_MORE_INPUT => break,
                        Err(_) => break,
                    }
                }
            }
            EncoderCommand::ForceKeyframe => {
                force_next_keyframe = true;
                let _ = resp_tx.send(EncoderResponse::KeyframeForcedAck);
            }
            EncoderCommand::Shutdown => {
                let _ = unsafe { transform.ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0) };
                let mut drained_count = 0;

                loop {
                    let sample_out: Option<IMFSample> = unsafe { MFCreateSample().ok() };
                    if let Ok(media_buf) = unsafe { MFCreateMemoryBuffer(MAX_ACCESS_UNIT_SIZE as u32) } {
                        if let Some(sb) = sample_out.as_ref() {
                            let _ = unsafe { sb.AddBuffer(&media_buf) };
                        }
                    }

                    let output_buffer = MFT_OUTPUT_DATA_BUFFER {
                        dwStreamID: 0,
                        pSample: std::mem::ManuallyDrop::new(sample_out),
                        dwStatus: 0,
                        pEvents: std::mem::ManuallyDrop::new(None),
                    };

                    let mut status = 0;
                    let mut buffers = [output_buffer];
                    let res = unsafe { transform.ProcessOutput(0, &mut buffers, &mut status) };

                    match res {
                        Ok(()) => {
                            if let Some(sample) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                                let sample_time_100ns = unsafe { sample.GetSampleTime() }.unwrap_or(0);
                                if let Ok(buf) = unsafe { sample.ConvertToContiguousBuffer() } {
                                    let mut ptr = null_mut();
                                    let mut max_len = 0;
                                    let mut cur_len = 0;
                                    if unsafe { buf.Lock(&mut ptr, Some(&mut max_len), Some(&mut cur_len)) }.is_ok() && cur_len > 0 {
                                        let raw_slice = unsafe { std::slice::from_raw_parts(ptr, cur_len as usize) };
                                        if let Ok((annexb_bytes, is_keyframe)) = annexb.process_sample(raw_slice) {
                                            drained_count += 1;
                                            let metrics = EncodeMetrics {
                                                frame_number: 999999,
                                                encode_duration_us: 0,
                                                sample_size_bytes: annexb_bytes.len(),
                                                is_keyframe,
                                                timestamp_qpc: 0,
                                                output_sample_time_100ns: sample_time_100ns,
                                            };
                                            let _ = resp_tx.send(EncoderResponse::EncodedSample {
                                                data: annexb_bytes,
                                                metrics,
                                            });
                                        }
                                        let _ = unsafe { buf.Unlock() };
                                    }
                                }
                            }
                        }
                        _ => break,
                    }
                }

                println!("[SYNC ENCODER SHUTDOWN] MFT_MESSAGE_COMMAND_DRAIN recovered {} buffered frames.", drained_count);
                let _ = resp_tx.send(EncoderResponse::ShutdownAck);
                break;
            }
        }
    }
}

fn enumerate_h264_encoders(hardware: bool) -> Result<Vec<(String, GUID, IMFTransform)>> {
    let flags = if hardware {
        MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER
    } else {
        MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER
    };

    let output_type = MFT_REGISTER_TYPE_INFO {
        guidMajorType: MFMediaType_Video,
        guidSubtype: MFVideoFormat_H264,
    };

    let mut activates_ptr: *mut Option<IMFActivate> = null_mut();
    let mut count: u32 = 0;

    unsafe {
        MFTEnumEx(
            MFT_CATEGORY_VIDEO_ENCODER,
            flags,
            None,
            Some(&output_type),
            &mut activates_ptr,
            &mut count,
        )?;
    }

    println!("[MFT ENUMERATION] Found {} total encoders for hardware={}", count, hardware);

    let mut result = Vec::new();
    if !activates_ptr.is_null() && count > 0 {
        let slice = unsafe { std::slice::from_raw_parts(activates_ptr, count as usize) };
        for (i, opt_act) in slice.iter().enumerate() {
            if let Some(act) = opt_act {
                if let Ok(mft) = unsafe { act.ActivateObject::<IMFTransform>() } {
                    let clsid = unsafe { act.GetGUID(&MFT_TRANSFORM_CLSID_Attribute) }.unwrap_or_default();

                    let mut name = format!("MFT_{}_{:?}", if hardware { "HW" } else { "SW" }, clsid);
                    let mut name_buf = [0u16; 256];
                    let mut name_len = 0;
                    if unsafe { act.GetString(&MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &mut name_buf, Some(&mut name_len)) }.is_ok() {
                        let name_str = String::from_utf16_lossy(&name_buf[..name_len as usize]);
                        if !name_str.is_empty() {
                            name = name_str;
                        }
                    }

                    let is_async = unsafe { mft.GetAttributes().and_then(|attr| attr.GetUINT32(&MF_TRANSFORM_ASYNC)) }.unwrap_or(0);

                    println!(
                        "[MFT ENUM #{}]: Name='{}' | CLSID={:?} | Async={} | Classification={}",
                        i + 1,
                        name,
                        clsid,
                        is_async == 1,
                        if hardware { "HARDWARE" } else { "SOFTWARE" }
                    );

                    result.push((name, clsid, mft));
                }
            }
        }
        unsafe { CoTaskMemFree(Some(activates_ptr as _)) };
    }

    Ok(result)
}

fn configure_encoder_media_types(mft: &IMFTransform, width: u32, height: u32) -> Result<()> {
    let mut selected_out_type: Option<IMFMediaType> = None;
    let mut type_index = 0;

    while let Ok(out_type) = unsafe { mft.GetOutputAvailableType(0, type_index) } {
        if let Ok(subtype) = unsafe { out_type.GetGUID(&MF_MT_SUBTYPE) } {
            if subtype == MFVideoFormat_H264 {
                selected_out_type = Some(out_type);
                break;
            }
        }
        type_index += 1;
    }

    let out_type = match selected_out_type {
        Some(t) => t,
        None => {
            let t: IMFMediaType = unsafe { MFCreateMediaType()? };
            unsafe {
                t.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
                t.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_H264)?;
            }
            t
        }
    };

    unsafe {
        out_type.SetUINT32(&MF_MT_AVG_BITRATE, 4_000_000)?;
        out_type.SetUINT64(&MF_MT_FRAME_SIZE, ((width as u64) << 32) | (height as u64))?;
        out_type.SetUINT64(&MF_MT_FRAME_RATE, (30u64 << 32) | 1u64)?;
        out_type.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
        mft.SetOutputType(0, &out_type, 0)?;
    }

    let mut selected_in_type: Option<IMFMediaType> = None;
    type_index = 0;

    while let Ok(in_type) = unsafe { mft.GetInputAvailableType(0, type_index) } {
        if let Ok(subtype) = unsafe { in_type.GetGUID(&MF_MT_SUBTYPE) } {
            if subtype == MFVideoFormat_NV12 {
                selected_in_type = Some(in_type);
                break;
            }
        }
        type_index += 1;
    }

    let in_type = match selected_in_type {
        Some(t) => t,
        None => {
            let t: IMFMediaType = unsafe { MFCreateMediaType()? };
            unsafe {
                t.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
                t.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12)?;
            }
            t
        }
    };

    unsafe {
        in_type.SetUINT64(&MF_MT_FRAME_SIZE, ((width as u64) << 32) | (height as u64))?;
        in_type.SetUINT64(&MF_MT_FRAME_RATE, (30u64 << 32) | 1u64)?;
        in_type.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
        mft.SetInputType(0, &in_type, 0)?;
    }

    Ok(())
}

fn create_dxgi_sample(texture: &ID3D11Texture2D, timestamp_qpc_100ns: i64) -> Result<IMFSample> {
    let buffer: IMFMediaBuffer = unsafe {
        MFCreateDXGISurfaceBuffer(&ID3D11Texture2D::IID, texture, 0, false)?
    };

    let sample: IMFSample = unsafe { MFCreateSample()? };

    unsafe {
        sample.AddBuffer(&buffer)?;
        sample.SetSampleTime(timestamp_qpc_100ns)?;
        sample.SetSampleDuration(333_333)?;
    }

    Ok(sample)
}

fn create_cpu_sample(
    _d3d_device: &ID3D11Device,
    _d3d_context: &ID3D11DeviceContext,
    _texture: &ID3D11Texture2D,
    width: u32,
    height: u32,
    timestamp_qpc_100ns: i64,
) -> Result<IMFSample> {
    let nv12_size = (width * height * 3 / 2) as usize;
    let media_buf: IMFMediaBuffer = unsafe { MFCreateMemoryBuffer(nv12_size as u32)? };
    let sample: IMFSample = unsafe { MFCreateSample()? };

    unsafe {
        media_buf.SetCurrentLength(nv12_size as u32)?;
        sample.AddBuffer(&media_buf)?;
        sample.SetSampleTime(timestamp_qpc_100ns)?;
        sample.SetSampleDuration(333_333)?;
    }

    Ok(sample)
}
