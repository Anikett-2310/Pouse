use std::ptr::null_mut;
use windows::core::{Interface, Result};
use windows::Win32::Graphics::Direct3D11::*;
use windows::Win32::Graphics::Dxgi::Common::*;

pub struct GpuVideoProcessor {
    pub video_device: ID3D11VideoDevice,
    pub video_context: ID3D11VideoContext,
    pub video_processor: ID3D11VideoProcessor,
    pub video_enum: ID3D11VideoProcessorEnumerator,
    pub nv12_texture: ID3D11Texture2D,
    pub output_view: ID3D11VideoProcessorOutputView,
    pub width: u32,
    pub height: u32,
}

impl GpuVideoProcessor {
    pub fn new(d3d_device: &ID3D11Device, d3d_context: &ID3D11DeviceContext, width: u32, height: u32) -> Result<Self> {
        let video_device: ID3D11VideoDevice = d3d_device.cast()?;
        let video_context: ID3D11VideoContext = d3d_context.cast()?;

        let content_desc = D3D11_VIDEO_PROCESSOR_CONTENT_DESC {
            InputFrameFormat: D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE,
            InputFrameRate: DXGI_RATIONAL { Numerator: 30, Denominator: 1 },
            InputWidth: width,
            InputHeight: height,
            OutputFrameRate: DXGI_RATIONAL { Numerator: 30, Denominator: 1 },
            OutputWidth: width,
            OutputHeight: height,
            Usage: D3D11_VIDEO_USAGE_PLAYBACK_NORMAL,
        };

        let video_enum = unsafe { video_device.CreateVideoProcessorEnumerator(&content_desc)? };
        let video_processor = unsafe { video_device.CreateVideoProcessor(&video_enum, 0)? };

        // Allocate NV12 target texture on GPU
        let nv12_desc = D3D11_TEXTURE2D_DESC {
            Width: width,
            Height: height,
            MipLevels: 1,
            ArraySize: 1,
            Format: DXGI_FORMAT_NV12,
            SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: (D3D11_BIND_RENDER_TARGET.0 | D3D11_BIND_SHADER_RESOURCE.0) as u32,
            CPUAccessFlags: 0,
            MiscFlags: 0,
        };

        let mut nv12_texture: Option<ID3D11Texture2D> = None;
        unsafe { d3d_device.CreateTexture2D(&nv12_desc, None, Some(&mut nv12_texture))? };
        let nv12_texture = nv12_texture.unwrap();

        let out_view_desc = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC {
            ViewDimension: D3D11_VPOV_DIMENSION_TEXTURE2D,
            Anonymous: D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC_0 {
                Texture2D: D3D11_TEX2D_VPOV { MipSlice: 0 },
            },
        };

        let mut output_view: Option<ID3D11VideoProcessorOutputView> = None;
        unsafe {
            video_device.CreateVideoProcessorOutputView(
                &nv12_texture,
                &video_enum,
                &out_view_desc,
                Some(&mut output_view),
            )?;
        };
        let output_view = output_view.unwrap();

        Ok(Self {
            video_device,
            video_context,
            video_processor,
            video_enum,
            nv12_texture,
            output_view,
            width,
            height,
        })
    }

    pub fn convert_bgra_to_nv12(
        &self,
        bgra_texture: &ID3D11Texture2D,
    ) -> Result<&ID3D11Texture2D> {
        let in_view_desc = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC {
            FourCC: 0,
            ViewDimension: D3D11_VPIV_DIMENSION_TEXTURE2D,
            Anonymous: D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC_0 {
                Texture2D: D3D11_TEX2D_VPIV { MipSlice: 0, ArraySlice: 0 },
            },
        };

        let mut input_view: Option<ID3D11VideoProcessorInputView> = None;
        unsafe {
            self.video_device.CreateVideoProcessorInputView(
                bgra_texture,
                &self.video_enum,
                &in_view_desc,
                Some(&mut input_view),
            )?;
        };
        let input_view = input_view.unwrap();

        let stream = D3D11_VIDEO_PROCESSOR_STREAM {
            Enable: true.into(),
            OutputIndex: 0,
            InputFrameOrField: 0,
            PastFrames: 0,
            FutureFrames: 0,
            ppFutureSurfaces: null_mut(),
            pInputSurface: std::mem::ManuallyDrop::new(Some(input_view)),
            ppPastSurfaces: null_mut(),
            ppFutureSurfacesRight: null_mut(),
            pInputSurfaceRight: std::mem::ManuallyDrop::new(None),
            ppPastSurfacesRight: null_mut(),
        };

        unsafe {
            self.video_context.VideoProcessorBlt(
                &self.video_processor,
                &self.output_view,
                0,
                &[stream],
            )?;
        }

        Ok(&self.nv12_texture)
    }
}
