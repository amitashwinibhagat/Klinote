//! Audio ingest and voice-activity detection.
//!
//! Scope: everything that turns a recording into the spans of speech an ASR
//! engine should look at. Live capture (AVAudioEngine in the Swift shell)
//! lands here as a buffer; file ingest is implemented for the CLI and for
//! batch processing of validation recordings.
//!
//! No model is required. VAD here is energy-based and deterministic, which is
//! enough to (a) segment files for ASR and (b) keep the pipeline testable
//! without downloading anything.

use scribe_core::{Result, ScribeError};

/// Mono audio, deinterleaved, in `[-1.0, 1.0]`.
#[derive(Debug, Clone)]
pub struct AudioBuffer {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
}

impl AudioBuffer {
    pub fn new(samples: Vec<f32>, sample_rate: u32) -> Self {
        Self {
            samples,
            sample_rate,
        }
    }

    pub fn duration_ms(&self) -> u64 {
        if self.sample_rate == 0 {
            return 0;
        }
        (self.samples.len() as u64 * 1000) / self.sample_rate as u64
    }

    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// Peak-normalise into a comfortable range without clipping.
    pub fn normalize(&self, target_peak: f32) -> Self {
        let peak = self.samples.iter().fold(0.0f32, |acc, s| acc.max(s.abs()));
        if peak <= f32::EPSILON || peak >= target_peak {
            return self.clone();
        }
        let gain = target_peak / peak;
        Self {
            samples: self.samples.iter().map(|s| s * gain).collect(),
            sample_rate: self.sample_rate,
        }
    }

    /// Linear resample. Good enough for VAD and for 16 kHz ASR input; the
    /// shell should hand us already-resampled audio where quality matters.
    pub fn resample_to(&self, target_rate: u32) -> Self {
        if target_rate == 0 || self.sample_rate == 0 || target_rate == self.sample_rate {
            return self.clone();
        }
        let ratio = target_rate as f64 / self.sample_rate as f64;
        let out_len = ((self.samples.len() as f64) * ratio).round() as usize;
        let mut out = Vec::with_capacity(out_len);

        for index in 0..out_len {
            let src = index as f64 / ratio;
            let left = src.floor() as usize;
            let frac = (src - left as f64) as f32;
            let a = self.samples.get(left).copied().unwrap_or(0.0);
            let b = self.samples.get(left + 1).copied().unwrap_or(a);
            out.push(a + (b - a) * frac);
        }

        Self {
            samples: out,
            sample_rate: target_rate,
        }
    }
}

/// A span of detected speech, in milliseconds from the start of the buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpeechSpan {
    pub start_ms: u64,
    pub end_ms: u64,
}

impl SpeechSpan {
    pub fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct VadConfig {
    /// Analysis frame length.
    pub frame_ms: u32,
    /// Frames quieter than this (dBFS) count as silence.
    pub silence_threshold_db: f32,
    /// Speech shorter than this is discarded as a click.
    pub min_speech_ms: u64,
    /// Silence longer than this ends a speech span.
    pub min_silence_ms: u64,
}

impl Default for VadConfig {
    fn default() -> Self {
        Self {
            frame_ms: 30,
            silence_threshold_db: -45.0,
            min_speech_ms: 250,
            min_silence_ms: 300,
        }
    }
}

/// Detect speech spans.
///
/// Energy VAD with hysteresis: entering speech needs a frame above threshold,
/// leaving it needs `min_silence_ms` of consecutive silence. Deterministic and
/// dependency-free, which keeps the whole pipeline runnable in CI.
pub fn detect_speech(audio: &AudioBuffer, config: VadConfig) -> Vec<SpeechSpan> {
    if audio.is_empty() || audio.sample_rate == 0 || config.frame_ms == 0 {
        return Vec::new();
    }

    let frame_len = (audio.sample_rate * config.frame_ms / 1000).max(1) as usize;
    let mut spans: Vec<SpeechSpan> = Vec::new();

    let mut in_speech = false;
    let mut span_start_ms: u64 = 0;
    let mut silence_run_ms: u64 = 0;

    let frame_ms = config.frame_ms as u64;

    for (index, frame) in audio.samples.chunks(frame_len).enumerate() {
        let frame_start_ms = index as u64 * frame_ms;

        let rms = (frame.iter().map(|s| s * s).sum::<f32>() / frame.len().max(1) as f32).sqrt();
        let db = if rms <= f32::EPSILON {
            f32::NEG_INFINITY
        } else {
            20.0 * rms.log10()
        };
        let is_speech = db >= config.silence_threshold_db;

        if is_speech {
            if !in_speech {
                in_speech = true;
                span_start_ms = frame_start_ms;
            }
            silence_run_ms = 0;
        } else if in_speech {
            silence_run_ms += frame_ms;
            if silence_run_ms >= config.min_silence_ms {
                let end_ms = frame_start_ms.saturating_sub(silence_run_ms - frame_ms);
                push_span(&mut spans, span_start_ms, end_ms, &config);
                in_speech = false;
                silence_run_ms = 0;
            }
        }
    }

    if in_speech {
        push_span(&mut spans, span_start_ms, audio.duration_ms(), &config);
    }

    spans
}

fn push_span(spans: &mut Vec<SpeechSpan>, start_ms: u64, end_ms: u64, config: &VadConfig) {
    let span = SpeechSpan { start_ms, end_ms };
    if span.duration_ms() < config.min_speech_ms {
        return;
    }
    // Merge spans separated by a gap shorter than the silence threshold.
    if let Some(last) = spans.last_mut() {
        if start_ms.saturating_sub(last.end_ms) < config.min_silence_ms {
            last.end_ms = end_ms;
            return;
        }
    }
    spans.push(span);
}

/// Load a WAV file into a mono `AudioBuffer`.
///
/// Supports the sample formats a clinic is likely to produce from a recorder
/// or an export: 16-bit and 32-bit PCM, and 32-bit float. Anything else is
/// rejected rather than silently mangled.
pub fn load_wav(path: impl AsRef<std::path::Path>) -> Result<AudioBuffer> {
    let path = path.as_ref();
    let reader = hound::WavReader::open(path)
        .map_err(|err| ScribeError::Audio(format!("{}: {err}", path.display())))?;
    let spec = reader.spec();

    let samples: Vec<f32> = match (spec.sample_format, spec.bits_per_sample) {
        (hound::SampleFormat::Float, 32) => reader
            .into_samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|err| ScribeError::Audio(err.to_string()))?,
        (hound::SampleFormat::Int, 16) => reader
            .into_samples::<i16>()
            .map(|sample| sample.map(|s| s as f32 / i16::MAX as f32))
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|err| ScribeError::Audio(err.to_string()))?,
        (hound::SampleFormat::Int, 32) => reader
            .into_samples::<i32>()
            .map(|sample| sample.map(|s| s as f32 / i32::MAX as f32))
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(|err| ScribeError::Audio(err.to_string()))?,
        (format, bits) => {
            return Err(ScribeError::Audio(format!(
                "unsupported WAV format {format:?} with {bits} bits per sample"
            )));
        }
    };

    let channels = spec.channels.max(1) as usize;
    let mono = if channels == 1 {
        samples
    } else {
        samples
            .chunks(channels)
            .map(|frame| frame.iter().sum::<f32>() / channels as f32)
            .collect()
    };

    Ok(AudioBuffer::new(mono, spec.sample_rate))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(freq: f32, ms: u64, rate: u32) -> Vec<f32> {
        let count = (rate as u64 * ms / 1000) as usize;
        (0..count)
            .map(|i| {
                let t = i as f32 / rate as f32;
                (2.0 * std::f32::consts::PI * freq * t).sin() * 0.5
            })
            .collect()
    }

    #[test]
    fn duration_is_computed_from_rate() {
        let audio = AudioBuffer::new(vec![0.0; 16_000], 16_000);
        assert_eq!(audio.duration_ms(), 1000);
    }

    #[test]
    fn detects_a_speech_burst_between_silences() {
        let rate = 16_000;
        let mut samples = vec![0.0f32; rate as usize]; // 1s silence
        samples.extend(tone(220.0, 800, rate)); // 0.8s speech
        samples.extend(vec![0.0f32; rate as usize]); // 1s silence
        let audio = AudioBuffer::new(samples, rate);

        let spans = detect_speech(&audio, VadConfig::default());
        assert_eq!(spans.len(), 1, "expected one span, got {spans:?}");
        let span = spans[0];
        assert!(span.start_ms >= 950 && span.start_ms <= 1100, "{span:?}");
        assert!(span.duration_ms() >= 700, "{span:?}");
    }

    #[test]
    fn silence_produces_no_spans() {
        let audio = AudioBuffer::new(vec![0.0; 16_000], 16_000);
        assert!(detect_speech(&audio, VadConfig::default()).is_empty());
    }

    #[test]
    fn resampling_preserves_duration() {
        let audio = AudioBuffer::new(tone(440.0, 500, 48_000), 48_000);
        let resampled = audio.resample_to(16_000);
        assert_eq!(resampled.sample_rate, 16_000);
        let delta = (resampled.duration_ms() as i64 - audio.duration_ms() as i64).abs();
        assert!(
            delta <= 2,
            "{} vs {}",
            resampled.duration_ms(),
            audio.duration_ms()
        );
    }

    #[test]
    fn loads_mono_16bit_wav() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("in.wav");
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: 16_000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&path, spec).unwrap();
        for _ in 0..1_600 {
            writer.write_sample::<i16>(1_000).unwrap();
            writer.write_sample::<i16>(-1_000).unwrap();
        }
        writer.finalize().unwrap();

        let audio = load_wav(&path).unwrap();
        assert_eq!(audio.sample_rate, 16_000);
        assert_eq!(audio.samples.len(), 1_600, "stereo should be downmixed");
        assert!(audio.samples.iter().all(|s| s.abs() < 0.1));
    }
}
