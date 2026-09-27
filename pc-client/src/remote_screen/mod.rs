pub mod annexb;
pub mod capture;
pub mod encoder;
pub mod host;
pub mod video_processor;


#[derive(Debug, Clone)]
pub struct EncodeMetrics {
    pub frame_number: u64,
    pub encode_duration_us: u64,
    pub sample_size_bytes: usize,
    pub is_keyframe: bool,
    pub timestamp_qpc: i64,
    pub output_sample_time_100ns: i64,
}

#[derive(Debug, Clone)]
pub struct SpikeReport {
    pub selected_mft_name: String,
    pub is_hardware: bool,
    pub zero_copy_verified: bool,
    pub same_d3d11_device: bool,
    pub input_dxgi_backed: bool,
    pub total_frames_captured: u64,
    pub total_frames_encoded: u64,
    pub dropped_frames: u64,
    pub idr_count: u64,
    pub avg_encode_time_ms: f64,
    pub p95_encode_time_ms: f64,
    pub max_encode_time_ms: f64,
    pub memory_growth_kb: i64,
    pub test_duration_secs: f64,
}
