//! Speaker diarisation.
//!
//! A consultation is almost always two voices (clinician + patient, or
//! clinician + owner in veterinary). [`TurnTakingDiarizer`] exploits that:
//! it alternates speakers across turn boundaries detected by silence gaps.
//! It is a heuristic, and it is labelled as one — role assignment is the weak
//! point of every ambient scribe, so the shell must always let a clinician
//! correct it with one click.
//!
//! A model-backed diarizer (pyannote segmentation + speaker embeddings, via
//! ONNX) implements the same trait and can be swapped in without touching the
//! pipeline. See `docs/engineering/ASR.md`.

use scribe_audio::{AudioBuffer, SpeechSpan};
use scribe_core::{Result, ScribeError, SpeakerId};

pub mod acoustic;

pub use acoustic::AcousticDiarizer;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiarizedTurn {
    pub start_ms: u64,
    pub end_ms: u64,
    pub speaker: SpeakerId,
}

#[derive(Debug, Clone, Default)]
pub struct Diarization {
    pub turns: Vec<DiarizedTurn>,
}

impl Diarization {
    /// Speaker active at `at_ms`, if any.
    pub fn speaker_at(&self, at_ms: u64) -> Option<SpeakerId> {
        self.turns
            .iter()
            .find(|turn| at_ms >= turn.start_ms && at_ms < turn.end_ms)
            .map(|turn| turn.speaker)
            .or_else(|| {
                // Fall back to the nearest preceding turn so a slightly
                // misaligned ASR segment still gets attributable.
                self.turns
                    .iter()
                    .rfind(|turn| turn.start_ms <= at_ms)
                    .map(|turn| turn.speaker)
            })
    }

    pub fn distinct_speakers(&self) -> Vec<SpeakerId> {
        let mut seen: Vec<SpeakerId> = Vec::new();
        for turn in &self.turns {
            if !seen.contains(&turn.speaker) {
                seen.push(turn.speaker);
            }
        }
        seen
    }
}

pub trait Diarizer {
    fn name(&self) -> &str;

    fn diarize(&self, audio: &AudioBuffer, spans: &[SpeechSpan]) -> Result<Diarization>;

    /// Diarise from segment timings alone, for when the shell did the
    /// recognition and there is no waveform to hand.
    ///
    /// Recognition is the shell's job on macOS — `SpeechAnalyzer` is a Swift
    /// API and cannot be called from here — so the pipeline can be given words
    /// and timings with no audio behind them. Turn-taking needs nothing but the
    /// gaps between segments and is fine. A model-backed diarizer needs the
    /// waveform, so the default **refuses** rather than returning one speaker
    /// for everything: a wrong role is worse than an unfiled sentence
    /// (`docs/engineering/ASR.md`), and every segment attributed to the
    /// clinician is exactly that failure, silently.
    fn diarize_segments(&self, _spans: &[SpeechSpan]) -> Result<Diarization> {
        Err(ScribeError::Diarisation(format!(
            "{} needs the audio and was given none; the shell must supply the recording",
            self.name()
        )))
    }
}

/// Two-speaker turn-taking heuristic.
#[derive(Debug, Clone, Copy)]
pub struct TurnTakingDiarizer {
    /// A silence at least this long is treated as a turn boundary.
    ///
    /// **This is coupled to the VAD, and it was wrong.** `scribe_audio`'s
    /// `detect_speech` closes a speech span only after `min_silence_ms` (300) of
    /// silence, so the gap between two spans it emits is *at least* 300 ms and
    /// typically exactly that. With the old default of 350 here, no gap the VAD
    /// could ever produce reached the threshold: the two constants sat 50 ms
    /// apart, the diariser never alternated, and every utterance in a two-voice
    /// consultation was attributed to the clinician. Measured with 7 spans, all
    /// gaps 300–330 ms.
    ///
    /// It must not exceed the VAD's `min_silence_ms`, or the mechanism is dead
    /// code that looks like it works.
    pub turn_gap_ms: u64,
    /// Maximum number of distinct speakers to emit.
    pub max_speakers: usize,
}

impl Default for TurnTakingDiarizer {
    fn default() -> Self {
        Self {
            // Equal to `scribe_audio::VadConfig::default().min_silence_ms`, not
            // below it. See the field comment.
            turn_gap_ms: 300,
            max_speakers: 2,
        }
    }
}

impl TurnTakingDiarizer {
    /// The whole heuristic. Both `diarize` and `diarize_segments` are this,
    /// because it never looked at the audio in the first place — only at the
    /// gaps between spans.
    fn turns(&self, spans: &[SpeechSpan]) -> Vec<DiarizedTurn> {
        let max_speakers = self.max_speakers.max(1) as u32;
        let mut turns = Vec::with_capacity(spans.len());
        let mut speaker_index: u32 = 0;

        for (index, span) in spans.iter().enumerate() {
            if index > 0 {
                let previous = spans[index - 1];
                let gap = span.start_ms.saturating_sub(previous.end_ms);
                if gap >= self.turn_gap_ms {
                    speaker_index = (speaker_index + 1) % max_speakers;
                }
            }
            turns.push(DiarizedTurn {
                start_ms: span.start_ms,
                end_ms: span.end_ms,
                speaker: SpeakerId::new(speaker_index),
            });
        }

        turns
    }
}

impl Diarizer for TurnTakingDiarizer {
    fn name(&self) -> &str {
        "turn-taking-v1"
    }

    fn diarize(&self, _audio: &AudioBuffer, spans: &[SpeechSpan]) -> Result<Diarization> {
        Ok(Diarization {
            turns: self.turns(spans),
        })
    }

    fn diarize_segments(&self, spans: &[SpeechSpan]) -> Result<Diarization> {
        Ok(Diarization {
            turns: self.turns(spans),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_audio() -> AudioBuffer {
        AudioBuffer::new(vec![0.0; 16_000], 16_000)
    }

    #[test]
    fn alternates_on_long_gaps() {
        let spans = vec![
            SpeechSpan {
                start_ms: 0,
                end_ms: 1000,
            },
            SpeechSpan {
                start_ms: 1000,
                end_ms: 2000,
            }, // no gap: same speaker
            SpeechSpan {
                start_ms: 3000,
                end_ms: 4000,
            }, // 1s gap: switch
            SpeechSpan {
                start_ms: 5000,
                end_ms: 6000,
            }, // 1s gap: switch back
        ];
        let diarization = TurnTakingDiarizer::default()
            .diarize(&empty_audio(), &spans)
            .unwrap();

        assert_eq!(diarization.turns.len(), 4);
        assert_eq!(diarization.turns[0].speaker, SpeakerId::new(0));
        assert_eq!(diarization.turns[1].speaker, SpeakerId::new(0));
        assert_eq!(diarization.turns[2].speaker, SpeakerId::new(1));
        assert_eq!(diarization.turns[3].speaker, SpeakerId::new(0));
        assert_eq!(diarization.distinct_speakers().len(), 2);
    }

    #[test]
    fn speaker_at_falls_back_to_preceding_turn() {
        let diarization = Diarization {
            turns: vec![DiarizedTurn {
                start_ms: 0,
                end_ms: 1000,
                speaker: SpeakerId::new(1),
            }],
        };
        assert_eq!(diarization.speaker_at(500), Some(SpeakerId::new(1)));
        assert_eq!(diarization.speaker_at(1500), Some(SpeakerId::new(1)));
    }

    /// The shell hands over timings with no audio, which is the path the macOS
    /// app now uses. Turn-taking must produce exactly what it produces when the
    /// audio is present, or the same recording would be diarised differently
    /// depending on which side of the FFI did the recognition.
    #[test]
    fn segment_only_diarisation_matches_the_audio_path() {
        let spans = vec![
            SpeechSpan {
                start_ms: 0,
                end_ms: 1000,
            },
            SpeechSpan {
                start_ms: 3000,
                end_ms: 4000,
            },
            SpeechSpan {
                start_ms: 5000,
                end_ms: 6000,
            },
        ];
        let diarizer = TurnTakingDiarizer::default();
        let with_audio = diarizer.diarize(&empty_audio(), &spans).unwrap();
        let without = diarizer.diarize_segments(&spans).unwrap();
        assert_eq!(with_audio.turns, without.turns);
    }

    /// The two constants are one decision, so they are asserted together.
    ///
    /// A VAD span is only closed after `min_silence_ms` of silence, so the gap
    /// between two spans is at least that long. If the turn threshold is higher,
    /// no gap the VAD can emit will ever change the speaker — and nothing fails,
    /// because one speaker is a perfectly valid answer. That is how a two-voice
    /// consultation came to be filed entirely under the clinician.
    #[test]
    fn the_turn_threshold_is_reachable_from_the_vad() {
        let vad = scribe_audio::VadConfig::default();
        let diarizer = TurnTakingDiarizer::default();
        assert!(
            diarizer.turn_gap_ms <= vad.min_silence_ms,
            "turn_gap_ms ({}) must not exceed the VAD's min_silence_ms ({}), or \
             diarisation silently finds one speaker",
            diarizer.turn_gap_ms,
            vad.min_silence_ms
        );
    }

    /// A diarizer that needs the waveform must say so. Returning one speaker
    /// for every segment instead would attribute the patient's words to the
    /// clinician, and nothing downstream could tell.
    #[test]
    fn a_diarizer_that_needs_audio_refuses_rather_than_guessing() {
        #[derive(Debug)]
        struct NeedsAudio;

        impl Diarizer for NeedsAudio {
            fn name(&self) -> &str {
                "needs-audio"
            }

            fn diarize(&self, _audio: &AudioBuffer, _spans: &[SpeechSpan]) -> Result<Diarization> {
                Ok(Diarization::default())
            }
        }

        let spans = vec![SpeechSpan {
            start_ms: 0,
            end_ms: 1000,
        }];
        let err = NeedsAudio.diarize_segments(&spans).unwrap_err();
        assert!(matches!(err, ScribeError::Diarisation(_)));
    }
}
