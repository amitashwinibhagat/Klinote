//! whisper.cpp backend for [`scribe_asr::AsrEngine`].
//!
//! Loads a GGUF model (the tinydiarize `-tdrz` variant for speaker
//! diarisation) and transcribes audio fully locally via [`whisper_rs`]
//! (Metal-accelerated on Apple Silicon).
//!
//! ## Download-on-first-use
//!
//! The model does **not** ship with the app. The shell downloads it on first
//! use from Hugging Face (`akashmjn/tinydiarize-whisper.cpp`, the upstream
//! tinydiarize project) into `~/Library/Application Support/Klinote/Models/` and
//! passes the path here. This crate never performs network I/O itself — the
//! Rust workspace stays network-free. Audio and text never leave the device.
//!
//! ## Role mapping
//!
//! SBD yields two anonymous speakers (A/B). Role mapping — which voice is the
//! clinician — is a judgment call the clinician owns; the engine defaults to
//! A=clinician, B=patient and the app exposes a one-tap swap.
//!
//! ## Verifiability
//!
//! Wholly deterministic given the model file: no randomness, no network, no
//! external processes. Paths are never logged.

use std::path::PathBuf;

use scribe_asr::{AsrEngine, AsrOptions, AsrOutput, AsrSegment};
use scribe_audio::{AudioBuffer, SpeechSpan};
use scribe_core::{Result, ScribeError, SpeakerId};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// The default model id/canonical filename the app downloads and loads.
pub const DEFAULT_MODEL_NAME: &str = "ggml-small.en-tdrz.bin";

/// A whisper.cpp engine bound to one GGUF model file.
///
/// Not cheap to construct (model load is heavy), so the app keeps one alive
/// and shares it through the pipeline.
#[derive(Debug)]
pub struct WhisperAsrEngine {
    context: WhisperContext,
    /// Number of decoder threads.
    n_threads: i32,
}

impl WhisperAsrEngine {
    /// Load a model from `path` (a GGUF file already on disk).
    ///
    /// * `model_path` — path to the `.gguf`/`.bin` model file.
    /// * `n_threads` — decoder threads; 0 means the whisper default.
    pub fn new(model_path: impl Into<PathBuf>, n_threads: u32) -> Result<Self> {
        let model_path = model_path.into();
        if !model_path.is_file() {
            return Err(ScribeError::Transcription(format!(
                "whisper model not found at {}",
                model_path.display()
            )));
        }

        let context =
            WhisperContext::new_with_params(&model_path, WhisperContextParameters::default())
                .map_err(|err| {
                    ScribeError::Transcription(format!("failed to load whisper model: {err}"))
                })?;

        Ok(Self {
            context,
            n_threads: n_threads.max(1) as i32,
        })
    }
}

impl AsrEngine for WhisperAsrEngine {
    fn name(&self) -> &str {
        "whisper-small-tdrz-sbd"
    }

    fn transcribe(
        &self,
        audio: &AudioBuffer,
        _spans: &[SpeechSpan],
        options: &AsrOptions,
    ) -> Result<AsrOutput> {
        // whisper.cpp wants monophonic 16 kHz f32 samples.
        let samples = audio.resample_to(16_000);

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 5 });
        // no_context=true keeps an encounter self-contained (no leakage from a
        // previous patient's words into the current transcript).
        params.set_no_context(true);
        params.set_n_threads(self.n_threads);
        // No progress/realtime noise on the console.
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_special(false);
        // Tiny diarize: emits per-segment speaker turn probabilities that we
        // read below. Requires the `-tdrz` model family.
        params.set_tdrz_enable(true);

        // The language hint must outlive `params` (the params type carries a
        // lifetime tied to the language string).
        let language_hint: Option<String> = options
            .language
            .as_deref()
            .map(|l| {
                l.split('-')
                    .next()
                    .unwrap_or("en")
                    .trim()
                    .to_ascii_lowercase()
            })
            .filter(|l| !l.is_empty());
        if let Some(lang) = &language_hint {
            params.set_language(Some(lang));
        }

        if options.translate_to_english {
            params.set_translate(true);
        }

        // One state per call, so concurrent use is safe and nothing leaks
        // between patients.
        let mut state = self
            .context
            .create_state()
            .map_err(|err| ScribeError::Transcription(format!("whisper state: {err}")))?;

        state.full(params, &samples.samples).map_err(|err| {
            ScribeError::Transcription(format!("whisper transcription failed: {err}"))
        })?;

        let n_segments = state.full_n_segments();
        let detected_lang = state.full_lang_id_from_state();

        let mut segments: Vec<AsrSegment> = Vec::with_capacity(n_segments.max(0) as usize);
        let mut current_speaker = SpeakerId::CLINICIAN;

        for index in 0..n_segments {
            let segment = state.get_segment(index).ok_or_else(|| {
                ScribeError::Transcription("whisper segment out of bounds".to_owned())
            })?;

            let text = segment
                .to_str_lossy()
                .map_err(|err| ScribeError::Transcription(format!("whisper segment text: {err}")))?
                .trim()
                .to_owned();
            if text.is_empty() {
                continue;
            }

            let start_ms = (segment.start_timestamp() as u64) * 10; // centiseconds → ms
            let end_ms = (segment.end_timestamp() as u64) * 10;

            let mut asr_segment = AsrSegment::new(start_ms, end_ms, text);
            // whisper does not expose per-segment recognition confidence here;
            // leave it None rather than record a misleading number.

            // `next_segment_speaker_turn` describes the *next* segment: if it
            // fires, the current segment belongs to the current speaker and
            // the following one flips. Applying it before assigning here was
            // off by one and mislabelled whole turns.
            asr_segment.speaker = Some(current_speaker);
            if segment.next_segment_speaker_turn() {
                current_speaker = SpeakerId::new(if current_speaker.0 == 0 { 1 } else { 0 });
            }

            segments.push(asr_segment);
        }

        // Merge consecutive segments from the same speaker so one continuous
        // turn doesn't fragment into many rows (the note generator works on
        // utterances; high fragmentation would misroute evidence).
        segments = merge_same_speaker(segments);

        Ok(AsrOutput {
            segments,
            language: if detected_lang >= 0 {
                // whisper language ids: 0 = en, ... map crudely by id.
                let langs = [
                    "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl",
                    "ar", "sv", "it", "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro",
                    "da", "hu", "ta", "no", "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy",
                    "sk", "te", "fa", "lv", "bn", "sr",
                ];
                langs
                    .get(detected_lang as usize)
                    .copied()
                    .unwrap_or("en")
                    .to_owned()
            } else {
                options.language.clone().unwrap_or_else(|| "en".to_owned())
            },
            engine: self.name().to_owned(),
        })
    }
}

/// Collapse consecutive `AsrSegment`s that share a speaker into one, keeping
/// the text order guaranteed and the timings covering the whole span.
fn merge_same_speaker(mut segments: Vec<AsrSegment>) -> Vec<AsrSegment> {
    let mut merged: Vec<AsrSegment> = Vec::with_capacity(segments.len());
    for segment in segments.drain(..) {
        match merged.last_mut() {
            Some(last) if last.speaker == segment.speaker && !last.text.is_empty() => {
                last.text.push(' ');
                last.text.push_str(segment.text.trim());
                last.end_ms = segment.end_ms;
            }
            _ => merged.push(segment),
        }
    }
    merged
}

const _: () = ();

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_model_is_reported_cleanly() {
        let err = WhisperAsrEngine::new("/nonexistent/model.bin", 4).unwrap_err();
        assert!(matches!(err, ScribeError::Transcription(_)));
    }

    #[test]
    fn default_model_constant_is_stable() {
        assert_eq!(DEFAULT_MODEL_NAME, "ggml-small.en-tdrz.bin");
    }

    #[test]
    fn merge_collapses_consecutive_same_speaker() {
        use scribe_asr::AsrSegment as S;
        let segments = vec![
            S {
                start_ms: 0,
                end_ms: 1000,
                text: "hello".into(),
                confidence: None,
                speaker: Some(SpeakerId::new(0)),
            },
            S {
                start_ms: 1000,
                end_ms: 2000,
                text: "there".into(),
                confidence: None,
                speaker: Some(SpeakerId::new(0)),
            },
            S {
                start_ms: 2000,
                end_ms: 3000,
                text: "bye".into(),
                confidence: None,
                speaker: Some(SpeakerId::new(1)),
            },
        ];
        let merged = merge_same_speaker(segments);
        assert_eq!(merged.len(), 2);
        assert_eq!(merged[0].text, "hello there");
        assert_eq!(merged[0].end_ms, 2000);
        assert_eq!(merged[1].text, "bye");
        assert_eq!(merged[1].speaker, Some(SpeakerId::new(1)));
    }
}
