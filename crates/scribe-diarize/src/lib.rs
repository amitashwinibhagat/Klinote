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
use scribe_core::{Result, SpeakerId};

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
}

/// Two-speaker turn-taking heuristic.
#[derive(Debug, Clone, Copy)]
pub struct TurnTakingDiarizer {
    /// A silence at least this long is treated as a turn boundary.
    pub turn_gap_ms: u64,
    /// Maximum number of distinct speakers to emit.
    pub max_speakers: usize,
}

impl Default for TurnTakingDiarizer {
    fn default() -> Self {
        Self {
            turn_gap_ms: 350,
            max_speakers: 2,
        }
    }
}

impl Diarizer for TurnTakingDiarizer {
    fn name(&self) -> &str {
        "turn-taking-v1"
    }

    fn diarize(&self, _audio: &AudioBuffer, spans: &[SpeechSpan]) -> Result<Diarization> {
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

        Ok(Diarization { turns })
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
}
