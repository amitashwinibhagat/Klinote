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

        // One pass over the recording, then repair it if the transcript does
        // not account for all of the audio (see `recover`).
        let (segments, _, detected_lang) =
            self.recover(&samples.samples, options, SpeakerId::CLINICIAN, 0)?;

        let segments = merge_same_speaker(segments);

        Ok(AsrOutput {
            segments,
            language: language_name(detected_lang, options),
            engine: self.name().to_owned(),
        })
    }
}

impl WhisperAsrEngine {
    /// Transcribe `samples`, then repair a transcript that does not account for
    /// all of it. Two different failures, one shape:
    ///
    ///  1. The transcript stops short of the audio — a discarded chunk.
    ///  2. The transcript claims to cover the audio but holds far too little
    ///     text, because the segment's end timestamp was stretched over the
    ///     discarded span. Density is the only signal left, so a window that
    ///     is implausibly sparse is halved and each half transcribed on its
    ///     own — a fresh window starting mid-speech does not see the end of a
    ///     turn and so does not give up early.
    ///
    /// This runs only when the result looks wrong, so an ordinary recording
    /// still costs exactly one pass.
    fn recover(
        &self,
        samples: &[f32],
        options: &AsrOptions,
        start_speaker: SpeakerId,
        depth: u32,
    ) -> Result<(Vec<AsrSegment>, SpeakerId, i32)> {
        let (segments, speaker, lang) = self.pass(samples, options, start_speaker)?;
        let span_ms = samples.len() as u64 / SAMPLES_PER_MS;

        if !is_sparse(spoken_chars(&segments), span_ms)
            || !is_splittable(span_ms)
            || depth >= MAX_SPLIT_DEPTH
        {
            return Ok((segments, speaker, lang));
        }

        let mid = samples.len() / 2;
        if mid == 0 {
            return Ok((segments, speaker, lang));
        }
        let mid_ms = mid as u64 / SAMPLES_PER_MS;
        let (mut first, mid_speaker, first_lang) =
            self.recover(&samples[..mid], options, start_speaker, depth + 1)?;
        let (mut second, end_speaker, _) =
            self.recover(&samples[mid..], options, mid_speaker, depth + 1)?;
        for segment in second.iter_mut() {
            segment.start_ms += mid_ms;
            segment.end_ms += mid_ms;
        }
        first.append(&mut second);

        // Keep the split only if it found substantially more. A marginal gain
        // is more likely to be a hallucination on silence than recovered
        // speech, so the bar is a doubling: the failures this repairs came back
        // at six and thirteen times their original. On audio that is genuinely
        // mostly silence the extra work is wasted, but nothing is lost.
        if split_wins(spoken_chars(&first), spoken_chars(&segments)) {
            Ok((first, end_speaker, first_lang))
        } else {
            Ok((segments, speaker, lang))
        }
    }

    /// One decode, plus a second pass over any audio it left untranscribed.
    fn pass(
        &self,
        samples: &[f32],
        options: &AsrOptions,
        start_speaker: SpeakerId,
    ) -> Result<(Vec<AsrSegment>, SpeakerId, i32)> {
        let total_ms = samples.len() as u64 / SAMPLES_PER_MS;
        let (mut segments, mut speaker, detected_lang) =
            self.decode(samples, options, start_speaker)?;

        for _ in 0..MAX_RECOVERY_PASSES {
            let covered_ms = segments.last().map(|s| s.end_ms).unwrap_or(0);
            if !tail_is_uncovered(total_ms, covered_ms) {
                break;
            }
            let from = (covered_ms * SAMPLES_PER_MS) as usize;
            if from >= samples.len() {
                break;
            }
            let rest = &samples[from..];
            if rest.len() < MIN_TAIL_SAMPLES {
                break;
            }

            // The discarded audio begins where the decoder decided a turn had
            // ended, so the answer that follows belongs to the other voice.
            // Continuing the same speaker instead merged the patient's only
            // words into the clinician's greeting, which misroutes the note.
            // It is still a guess, and it is recoverable: the margin offers
            // Swap for exactly this.
            let (mut more, next_speaker, _) = self.decode(rest, options, other_voice(speaker))?;
            if more.is_empty() {
                break;
            }
            // The recovery pass decodes a slice, so its timestamps start at
            // zero. Shift them back onto the recording's clock.
            for segment in more.iter_mut() {
                segment.start_ms += covered_ms;
                segment.end_ms += covered_ms;
            }

            let recovered_to = more.last().map(|s| s.end_ms).unwrap_or(covered_ms);
            if recovered_to < covered_ms + MIN_PROGRESS_MS {
                // No real progress: stop rather than loop on the same audio.
                break;
            }
            speaker = next_speaker;
            segments.append(&mut more);
        }

        Ok((segments, speaker, detected_lang))
    }
}

/// whisper.cpp discards the remainder of a 30-second chunk when a segment ends
/// on a lone trailing timestamp token (`single timestamp ending - skip entire
/// chunk`, whisper.cpp §2629). The model emits that token when it decides the
/// audio has ended — which it does prematurely after a short opening turn, so a
/// fifteen-second consult can come back with only its first four seconds
/// transcribed and nothing anywhere saying so.
///
/// The discarded audio is still in the recording, so transcribe it again.
fn tail_is_uncovered(total_ms: u64, covered_ms: u64) -> bool {
    total_ms.saturating_sub(covered_ms) >= MIN_UNCOVERED_MS
}

/// The voice a turn boundary lands on.
fn other_voice(speaker: SpeakerId) -> SpeakerId {
    SpeakerId::new(if speaker.0 == 0 { 1 } else { 0 })
}

/// Characters of transcript text, which is all the density check needs.
fn spoken_chars(segments: &[AsrSegment]) -> usize {
    segments.iter().map(|s| s.text.chars().count()).sum()
}

/// Conversational speech runs around fifteen characters a second. Well under
/// half of that, over audio long enough to hold a sentence, means the decoder
/// stopped early however the timestamps read.
fn is_sparse(chars: usize, span_ms: u64) -> bool {
    if span_ms == 0 {
        return false;
    }
    (chars as f64) / (span_ms as f64 / 1000.0) < MIN_PLAUSIBLE_CHARS_PER_SEC
}

/// Does the split hold substantially more text than the pass it replaces?
///
/// A marginal gain is more likely to be a hallucination on silence than
/// recovered speech, so the bar is a doubling: the failures this repairs came
/// back at six and thirteen times their original.
/// Even a doubling means little when both totals are near zero, so the split
/// must also have found at least this much. A few words is the least that
/// could be a sentence the decoder skipped.
const MIN_SPLIT_GAIN_CHARS: usize = 40;

fn split_wins(recovered: usize, original: usize) -> bool {
    recovered >= MIN_SPLIT_GAIN_CHARS && recovered > original.saturating_mul(2)
}

/// Halving costs up to one extra decode per level, so the extra work is bounded
/// by the depth — but only if the recording is short. A long quiet consult
/// would otherwise pay several times over to be told it is quiet, and the
/// failures worth repairing are short: the observed ones were thirteen to
/// fifty-one seconds. A sparse transcript longer than this is left as it is.
fn is_splittable(span_ms: u64) -> bool {
    (MIN_SPLIT_SPAN_MS..=MAX_SPLIT_SPAN_MS).contains(&span_ms)
}

fn language_name(detected_lang: i32, options: &AsrOptions) -> String {
    if detected_lang < 0 {
        return options.language.clone().unwrap_or_else(|| "en".to_owned());
    }
    let langs = [
        "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv",
        "it", "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no",
        "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr",
    ];
    langs
        .get(detected_lang as usize)
        .copied()
        .unwrap_or("en")
        .to_owned()
}

/// Audio is resampled to 16 kHz, so there are 16 samples in a millisecond.
const SAMPLES_PER_MS: u64 = 16;
/// Half a second of audio is the least worth a second pass.
const MIN_TAIL_SAMPLES: usize = 8_000;
/// A gap smaller than this is a normal pause, not a discarded chunk.
const MIN_UNCOVERED_MS: u64 = 1_000;
/// Each pass must move the end of the transcript forward by this much.
const MIN_PROGRESS_MS: u64 = 500;
/// Bounded: a pathological file must not turn one transcription into many.
const MAX_RECOVERY_PASSES: usize = 4;
/// Below this the transcript is not plausible speech and is worth splitting.
const MIN_PLAUSIBLE_CHARS_PER_SEC: f64 = 6.0;
/// Shorter than this is not worth halving; the tail pass already covers it.
const MIN_SPLIT_SPAN_MS: u64 = 8_000;
/// Longer than this is not halved: the extra work stops being worth it.
const MAX_SPLIT_SPAN_MS: u64 = 120_000;
/// Halving ends around four seconds, which is shorter than any turn.
const MAX_SPLIT_DEPTH: u32 = 3;

impl WhisperAsrEngine {
    /// One `whisper_full` over `samples`, returning segments, the speaker the
    /// next call should continue from, and whisper's detected language id.
    fn decode(
        &self,
        samples: &[f32],
        options: &AsrOptions,
        start_speaker: SpeakerId,
    ) -> Result<(Vec<AsrSegment>, SpeakerId, i32)> {
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

        // Bias the decoder toward real generics. Does not rewrite the transcript.
        params.set_initial_prompt(scribe_core::formulary::WHISPER_PROMPT);

        // One state per call, so concurrent use is safe and nothing leaks
        // between patients.
        let mut state = self
            .context
            .create_state()
            .map_err(|err| ScribeError::Transcription(format!("whisper state: {err}")))?;

        state.full(params, samples).map_err(|err| {
            ScribeError::Transcription(format!("whisper transcription failed: {err}"))
        })?;

        let n_segments = state.full_n_segments();
        let detected_lang = state.full_lang_id_from_state();

        let mut segments: Vec<AsrSegment> = Vec::with_capacity(n_segments.max(0) as usize);
        // Continues from the previous pass, so a recovered tail does not
        // restart the voice labels and relabel Voice A as Voice B.
        let mut current_speaker = start_speaker;

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
                current_speaker = other_voice(current_speaker);
            }

            segments.push(asr_segment);
        }

        Ok((segments, current_speaker, detected_lang))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_short_tail_is_left_alone() {
        // Ordinary pauses are not discarded chunks.
        assert!(!tail_is_uncovered(20_000, 20_000));
        assert!(!tail_is_uncovered(20_000, 19_500));
        assert!(tail_is_uncovered(20_000, 19_000));
    }

    #[test]
    fn a_transcript_that_stops_early_is_spotted() {
        // Half a second of a thirty-second recording.
        assert!(tail_is_uncovered(30_000, 500));
        // The end is claimed but only a greeting is there — the case the
        // timestamps hide, which is why density is checked as well.
        assert!(is_sparse(67, 13_470));
        assert!(is_sparse(81, 51_250));
        assert!(is_sparse(114, 32_360));
    }

    #[test]
    fn ordinary_speech_is_not_sparse() {
        // Conversational speech is roughly fifteen characters a second.
        assert!(!is_sparse(247, 13_470));
        assert!(!is_sparse(1_028, 51_250));
        assert!(!is_sparse(1_708, 108_000));
        // Silence has no text; it must not be mistaken for a failed decode,
        // or every quiet recording would be transcribed four times over.
        assert!(!is_sparse(0, 0));
    }

    #[test]
    fn only_short_recordings_are_worth_halving() {
        assert!(!is_splittable(4_000));
        assert!(is_splittable(13_470));
        assert!(is_splittable(51_250));
        assert!(is_splittable(120_000));
        // A fifteen-minute consult must not pay four passes to be told it is
        // quiet; it is left sparse instead.
        assert!(!is_splittable(900_000));
    }

    #[test]
    fn a_marginal_split_is_not_believed() {
        // The observed recoveries, in the order they were measured.
        assert!(split_wins(660, 114));
        assert!(split_wins(1_027, 81));
        // A couple of extra characters is not recovered speech, and on silence
        // both totals are near zero, where a doubling means nothing.
        assert!(!split_wins(70, 67));
        assert!(!split_wins(12, 8));
        // Doubling from nothing is not evidence: silence hallucinates a word
        // or two, and that must not replace a transcript that was merely thin.
        assert!(!split_wins(1, 0));
        assert!(!split_wins(39, 0));
        assert!(split_wins(40, 0));
    }

    #[test]
    fn the_recovered_voice_is_the_other_one() {
        assert_eq!(other_voice(SpeakerId::new(0)).0, 1);
        assert_eq!(other_voice(SpeakerId::new(1)).0, 0);
    }

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
