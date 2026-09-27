use std::collections::VecDeque;
use std::ptr::null_mut;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::Instant;
use windows::core::{Interface, Result, GUID, HRESULT};
use windows::Win32::Graphics::Direct3D::*;
use windows::Win32::Graphics::Direct3D11::*;
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::*;

fn main() -> Result<()> {
    unsafe {
        CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
        MFStartup(MF_VERSION, MFSTARTUP_FULL)?;
    }

    println!("==================================================");
    println!("  MFT DIAGNOSTIC: 2-THREAD ASYNC MFT ARCHITECTURE  ");
    println!("==================================================");

    if let Err(e) = test_async_nvenc_2thread() {
        println!("Async NVENC Test Failed: {:?}", e);
    }

    unsafe {
        let _ = MFShutdown();
        CoUninitialize();
    }
    Ok(())
}

fn test_async_nvenc_2thread() -> Result<()> {
    // 1. Create D3D11 Device
    let mut d3d_device: Option<ID3D11Device> = None;
    let mut d3d_context: Option<ID3D11DeviceContext> = None;
    let mut feature_level = D3D_FEATURE_LEVEL_11_0;

    unsafe {
        D3D11CreateDevice(
            None,
            D3D_DRIVER_TYPE_HARDWARE,
            None,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
            Some(&[D3D_FEATURE_LEVEL_11_0]),
            D3D11_SDK_VERSION,
            Some(&mut d3d_device),
            Some(&mut feature_level),
            Some(&mut d3d_context),
        )?;
    }
    let d3d_device = d3d_device.unwrap();

    // 2. Create DXGI Device Manager
    let mut reset_token = 0;
    let mut dxgi_mgr_opt: Option<IMFDXGIDeviceManager> = None;
    unsafe { MFCreateDXGIDeviceManager(&mut reset_token, &mut dxgi_mgr_opt)? };
    let dxgi_mgr = dxgi_mgr_opt.unwrap();
    unsafe { dxgi_mgr.ResetDevice(&d3d_device, reset_token)? };

    // 3. Find NVIDIA HW MFT
    let output_type = MFT_REGISTER_TYPE_INFO {
        guidMajorType: MFMediaType_Video,
        guidSubtype: MFVideoFormat_H264,
    };

    let mut activates_ptr: *mut Option<IMFActivate> = null_mut();
    let mut count: u32 = 0;

    unsafe {
        MFTEnumEx(
            MFT_CATEGORY_VIDEO_ENCODER,
            MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER,
            None,
            Some(&output_type),
            &mut activates_ptr,
            &mut count,
        )?;
    }

    if activates_ptr.is_null() || count == 0 {
        return Err(windows::core::Error::new(HRESULT(-1), "No HW encoders found"));
    }

    let slice = unsafe { std::slice::from_raw_parts(activates_ptr, count as usize) };
    let mut mft_opt: Option<IMFTransform> = None;

    for act in slice.iter().flatten() {
        if let Ok(mft) = unsafe { act.ActivateObject::<IMFTransform>() } {
            if let Ok(attr) = unsafe { mft.GetAttributes() } {
                let _ = unsafe { attr.SetUINT32(&MF_TRANSFORM_ASYNC_UNLOCK, 1) };
            }
            let param = dxgi_mgr.as_raw() as usize;
            if unsafe { mft.ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, param) }.is_ok() {
                mft_opt = Some(mft);
                break;
            }
        }
    }
    unsafe { CoTaskMemFree(Some(activates_ptr as _)) };

    let mft = mft_opt.ok_or_else(|| windows::core::Error::new(HRESULT(-1), "Failed to activate HW MFT"))?;

    // 4. Configure Types
    let width = 1280u32;
    let height = 720u32;

    let out_type: IMFMediaType = unsafe { MFCreateMediaType()? };
    unsafe {
        out_type.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
        out_type.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_H264)?;
        out_type.SetUINT32(&MF_MT_AVG_BITRATE, 4_000_000)?;
        out_type.SetUINT64(&MF_MT_FRAME_SIZE, ((width as u64) << 32) | (height as u64))?;
        out_type.SetUINT64(&MF_MT_FRAME_RATE, (30u64 << 32) | 1u64)?;
        out_type.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
        mft.SetOutputType(0, &out_type, 0)?;
    }

    let in_type: IMFMediaType = unsafe { MFCreateMediaType()? };
    unsafe {
        in_type.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
        in_type.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_NV12)?;
        in_type.SetUINT64(&MF_MT_FRAME_SIZE, ((width as u64) << 32) | (height as u64))?;
        in_type.SetUINT64(&MF_MT_FRAME_RATE, (30u64 << 32) | 1u64)?;
        in_type.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32)?;
        mft.SetInputType(0, &in_type, 0)?;
    }

    let stream_info = unsafe { mft.GetOutputStreamInfo(0)? };
    let provides_samples = (stream_info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 as u32 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0 as u32)) != 0;

    let event_gen: IMFMediaEventGenerator = mft.cast()?;

    // Send streaming start messages
    unsafe {
        mft.ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0)?;
        mft.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0)?;
        mft.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0)?;
    }

#[derive(Clone)]
struct SendRaw<T>(pub T);
unsafe impl<T> Send for SendRaw<T> {}
unsafe impl<T> Sync for SendRaw<T> {}

impl SendRaw<IMFMediaEventGenerator> {
    pub fn get_event(&self) -> Result<IMFMediaEvent> {
        unsafe { self.0.GetEvent(MF_EVENT_FLAG_NONE) }
    }
}

    // Create event channel and spawn event reader thread
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

    // Create NV12 Texture for testing
    let tex_desc = D3D11_TEXTURE2D_DESC {
        Width: width,
        Height: height,
        MipLevels: 1,
        ArraySize: 1,
        Format: windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_NV12,
        SampleDesc: windows::Win32::Graphics::Dxgi::Common::DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
        Usage: D3D11_USAGE_DEFAULT,
        BindFlags: (D3D11_BIND_RENDER_TARGET.0 | D3D11_BIND_SHADER_RESOURCE.0) as u32,
        CPUAccessFlags: 0,
        MiscFlags: 0,
    };
    let mut nv12_tex: Option<ID3D11Texture2D> = None;
    unsafe { d3d_device.CreateTexture2D(&tex_desc, None, Some(&mut nv12_tex))? };
    let nv12_tex = nv12_tex.unwrap();

    let mut pending_inputs: VecDeque<(IMFSample, Instant, i64)> = VecDeque::new();
    let mut needed_inputs: usize = 0;
    let mut frame_count = 0;
    let mut encoded_count = 0;

    // Simulate 60 frame submissions at 30 FPS pacing (33ms per frame)
    let start_time = Instant::now();

    for f in 1..=60 {
        // Create sample
        let buffer: IMFMediaBuffer = unsafe { MFCreateDXGISurfaceBuffer(&ID3D11Texture2D::IID, &nv12_tex, 0, false)? };
        let sample: IMFSample = unsafe { MFCreateSample()? };
        let sample_time_100ns = (f as i64) * 333_333;
        unsafe {
            sample.AddBuffer(&buffer)?;
            sample.SetSampleTime(sample_time_100ns)?;
            sample.SetSampleDuration(333_333)?;
        }

        // Push to pending queue
        pending_inputs.push_back((sample, Instant::now(), sample_time_100ns));
        frame_count += 1;

        // Process pending events
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
                if unsafe { mft.ProcessOutput(0, &mut buffers, &mut out_status) }.is_ok() {
                    if let Some(s) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                        let out_time = unsafe { s.GetSampleTime() }.unwrap_or(0);
                        let len = unsafe { s.GetTotalLength() }.unwrap_or(0);
                        encoded_count += 1;
                        let delay_ms = (Instant::now() - start_time).as_millis();
                        println!(" <= OUTPUT #{}: size={} bytes, sample_time={}ms | Elapsed={}ms", encoded_count, len, out_time / 10_000, delay_ms);
                    }
                }
            }
        }

        // Submit pending samples if MFT needs input
        while needed_inputs > 0 && !pending_inputs.is_empty() {
            let (inp_sample, _sub_time, _stm) = pending_inputs.pop_front().unwrap();
            unsafe {
                let _ = mft.ProcessInput(0, &inp_sample, 0);
            }
            needed_inputs -= 1;
        }

        std::thread::sleep(std::time::Duration::from_millis(33));
    }

    println!("Submitted all 60 frames. Triggering MFT_MESSAGE_COMMAND_DRAIN...");
    unsafe { mft.ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0)?; }

    // Wait for remaining events until METransformDrainComplete
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
            if unsafe { mft.ProcessOutput(0, &mut buffers, &mut out_status) }.is_ok() {
                if let Some(s) = std::mem::ManuallyDrop::into_inner(buffers[0].pSample.clone()) {
                    let out_time = unsafe { s.GetSampleTime() }.unwrap_or(0);
                    let len = unsafe { s.GetTotalLength() }.unwrap_or(0);
                    encoded_count += 1;
                    println!(" <= DRAIN OUTPUT #{}: size={} bytes, sample_time={}ms", encoded_count, len, out_time / 10_000);
                }
            }
        } else if ev_type == METransformDrainComplete.0 as u32 {
            println!(" *** METransformDrainComplete RECEIVED! Total encoded={} / Submitted={} ***", encoded_count, frame_count);
            break;
        }
    }

    Ok(())
}



