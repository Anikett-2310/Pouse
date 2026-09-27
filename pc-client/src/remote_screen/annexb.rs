pub const MAX_ACCESS_UNIT_SIZE: usize = 4 * 1024 * 1024; // 4 MB safety ceiling

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NalType {
    SliceNonIdr,
    SliceIdr,
    Sps,
    Pps,
    Other(u8),
}

impl NalType {
    pub fn from_byte(byte: u8) -> Self {
        match byte & 0x1F {
            1 => NalType::SliceNonIdr,
            5 => NalType::SliceIdr,
            7 => NalType::Sps,
            8 => NalType::Pps,
            other => NalType::Other(other),
        }
    }
}

pub struct AnnexBProcessor {
    cached_sps: Option<Vec<u8>>,
    cached_pps: Option<Vec<u8>>,
}

impl AnnexBProcessor {
    pub fn new() -> Self {
        Self {
            cached_sps: None,
            cached_pps: None,
        }
    }

    pub fn set_extra_data(&mut self, extra_data: &[u8]) {
        let nals = parse_annexb_or_avcc(extra_data);
        for nal in nals {
            if nal.is_empty() { continue; }
            let nal_type = NalType::from_byte(nal[0]);
            if nal_type == NalType::Sps {
                self.cached_sps = Some(nal);
            } else if nal_type == NalType::Pps {
                self.cached_pps = Some(nal);
            }
        }
    }

    pub fn process_sample(&mut self, raw_bytes: &[u8]) -> Result<(Vec<u8>, bool), String> {
        if raw_bytes.len() > MAX_ACCESS_UNIT_SIZE {
            return Err(format!(
                "Encoded access unit exceeded maximum size ceiling: {} bytes > {} bytes ceiling",
                raw_bytes.len(),
                MAX_ACCESS_UNIT_SIZE
            ));
        }

        let nals = parse_annexb_or_avcc(raw_bytes);
        if nals.is_empty() {
            return Err("Empty or invalid NAL unit payload".to_string());
        }

        let mut contains_idr = false;
        let mut contains_sps = false;
        let mut contains_pps = false;

        for nal in &nals {
            if nal.is_empty() { continue; }
            match NalType::from_byte(nal[0]) {
                NalType::Sps => {
                    contains_sps = true;
                    self.cached_sps = Some(nal.clone());
                }
                NalType::Pps => {
                    contains_pps = true;
                    self.cached_pps = Some(nal.clone());
                }
                NalType::SliceIdr => {
                    contains_idr = true;
                }
                _ => {}
            }
        }

        let mut output = Vec::with_capacity(raw_bytes.len() + 128);

        // If this sample is an IDR keyframe but does not include SPS/PPS, prepend cached SPS/PPS
        if contains_idr && (!contains_sps || !contains_pps) {
            if let Some(ref sps) = self.cached_sps {
                output.extend_from_slice(&[0, 0, 0, 1]);
                output.extend_from_slice(sps);
            }
            if let Some(ref pps) = self.cached_pps {
                output.extend_from_slice(&[0, 0, 0, 1]);
                output.extend_from_slice(pps);
            }
        }

        for nal in nals {
            output.extend_from_slice(&[0, 0, 0, 1]);
            output.extend_from_slice(&nal);
        }

        if output.len() > MAX_ACCESS_UNIT_SIZE {
            return Err(format!(
                "Final Annex-B access unit size exceeded limit: {} bytes",
                output.len()
            ));
        }

        Ok((output, contains_idr))
    }
}

pub fn parse_annexb_or_avcc(data: &[u8]) -> Vec<Vec<u8>> {
    let mut nals = Vec::new();
    if data.len() < 4 {
        return nals;
    }

    if (data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1)
        || (data[0] == 0 && data[1] == 0 && data[2] == 1)
    {
        let mut i = 0;
        let len = data.len();
        let mut start_indices = Vec::new();

        while i < len {
            if i + 3 < len && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1 {
                start_indices.push((i, 4));
                i += 4;
            } else if i + 2 < len && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
                start_indices.push((i, 3));
                i += 3;
            } else {
                i += 1;
            }
        }

        for idx in 0..start_indices.len() {
            let (start, prefix_len) = start_indices[idx];
            let nal_start = start + prefix_len;
            let nal_end = if idx + 1 < start_indices.len() {
                start_indices[idx + 1].0
            } else {
                len
            };

            if nal_start < nal_end {
                nals.push(data[nal_start..nal_end].to_vec());
            }
        }
    } else {
        let mut offset = 0;
        while offset + 4 <= data.len() {
            let nal_len = u32::from_be_bytes([
                data[offset],
                data[offset + 1],
                data[offset + 2],
                data[offset + 3],
            ]) as usize;
            offset += 4;
            if offset + nal_len <= data.len() {
                nals.push(data[offset..offset + nal_len].to_vec());
                offset += nal_len;
            } else {
                break;
            }
        }
    }

    nals
}
