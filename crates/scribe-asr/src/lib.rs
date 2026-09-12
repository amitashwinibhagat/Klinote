//! Speech recognition abstraction.
//!
//! The trait is deliberately thin so the shell can pick the best backend per
//! OS version without the rest of the system caring:
//!
//! | Backend | Where | Notes |
//! |---|---|---|
//! | Apple `SpeechAnalyzer` | Swift shell, macOS 26+ | preferred on device; streaming, notarisation-independent |
//! | `whisper.cpp` | Rust, any macOS | portable fallback; see `docs/engineering/ASR.md` |
//! | `sherpa-onnx` | Rust, any macOS | streaming + diarisation models |
//! | [`MockAsrEngine`] | tests, CI | no model, no download |
//!
//! The Rust core always speaks [`AsrOutput`]; the shell is free to implement
//! `AsrEngine` in Swift and hand the result across the FFI boundary.

use scribe_audio::{AudioBuffer, SpeechSpan};
use scribe_core::{Result, SpeakerId};

#[derive(Debug, Clone, Default)]
pub struct AsrOptions {
    /// BCP-47-ish language hint, e.g. `"en-GB"`.
    pub language: Option<String>,
    /// Ask the backend to translate into English rather than transcribe.
    pub translate_to_english: bool,
}

/// One recognised span. Timings are relative to the start of the audio.
#[derive(Debug, Clone, PartialEq)]
pub struct AsrSegment {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub confidence: Option<f32>,
    /// Speaker annotation when the backend has one (e.g. whisper.cpp SBD).
    /// The pipeline prefers this over silence-based diarisation.
    pub speaker: Option<SpeakerId>,
}

impl AsrSegment {
    pub fn new(start_ms: u64, end_ms: u64, text: impl Into<String>) -> Self {
        Self {
            start_ms,
            end_ms,
            text: text.into(),
            confidence: None,
            speaker: None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AsrOutput {
    pub segments: Vec<AsrSegment>,
    pub language: String,
    pub engine: String,
}

impl AsrOutput {
    pub fn text(&self) -> String {
        self.segments
            .iter()
            .map(|s| s.text.trim())
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" ")
    }
}

pub trait AsrEngine {
    /// Stable identity recorded on the transcript, e.g. `"apple-speechanalyzer"`.
    fn name(&self) -> &str;

    /// Transcribe `audio`, optionally restricted to the given speech spans.
    /// Implementations must not perform any network I/O.
    fn transcribe(
        &self,
        audio: &AudioBuffer,
        spans: &[SpeechSpan],
        options: &AsrOptions,
    ) -> Result<AsrOutput>;
}

/// Deterministic stand-in used by tests, CI and the `--engine mock` CLI path.
///
/// It emits clearly-labelled synthetic clinical dialogue so the pipeline can
/// be exercised end to end without a model. Never ship a build that defaults
/// to this engine in front of a clinician.
#[derive(Debug, Default, Clone, Copy)]
pub struct MockAsrEngine;

const MOCK_CORPUS: &[&str] = &[
    "Good morning, what brings you in today?",
    "I have had a sore throat for four days and it hurts when I swallow.",
    "Any fever or cough?",
    "No fever, but I have been feeling tired.",
    "On examination the temperature is 37.2 and the throat shows erythema.",
    "My impression is a viral upper respiratory tract infection.",
    "Plan: rest and fluids, paracetamol as needed.",
    "Follow up in one week if not improving.",
];

impl AsrEngine for MockAsrEngine {
    fn name(&self) -> &str {
        "mock"
    }

    fn transcribe(
        &self,
        audio: &AudioBuffer,
        spans: &[SpeechSpan],
        options: &AsrOptions,
    ) -> Result<AsrOutput> {
        let duration_ms = audio.duration_ms();
        let segments = spans
            .iter()
            .enumerate()
            .map(|(index, span)| {
                let end = span.end_ms.min(duration_ms.max(span.end_ms));
                AsrSegment::new(span.start_ms, end, MOCK_CORPUS[index % MOCK_CORPUS.len()])
            })
            .collect();

        Ok(AsrOutput {
            segments,
            language: options.language.clone().unwrap_or_else(|| "en".to_owned()),
            engine: self.name().to_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mock_engine_emits_one_segment_per_span() {
        let audio = AudioBuffer::new(vec![0.0; 16_000 * 10], 16_000);
        let spans = vec![
            SpeechSpan {
                start_ms: 0,
                end_ms: 1000,
            },
            SpeechSpan {
                start_ms: 2000,
                end_ms: 3000,
            },
        ];
        let out = MockAsrEngine
            .transcribe(&audio, &spans, &AsrOptions::default())
            .unwrap();
        assert_eq!(out.segments.len(), 2);
        assert_eq!(out.segments[0].start_ms, 0);
        assert_eq!(out.engine, "mock");
        assert!(!out.text().is_empty());
    }
}
