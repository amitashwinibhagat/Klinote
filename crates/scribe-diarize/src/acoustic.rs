//! Acoustic speaker separation for two voices.
//!
//! The turn-taking heuristic in [`crate::TurnTakingDiarizer`] reads the silences
//! *between* spans, which is enough when the transcription backend also labels
//! speakers (whisper.cpp's SBD did). `SpeechAnalyzer` does not, and it reports
//! contiguous ranges, so there is no gap to read at all. Measured on the
//! two-voice bench: 5 speaker changes found where the consultation had 17, and
//! 52% of segments given the right role — a coin flip.
//!
//! Silence cannot separate two people talking back to back. Voice can. This
//! measures two cheap features per speech span — fundamental frequency and
//! zero-crossing rate — and clusters the spans into two speakers.
//!
//! Deliberately no model and no download: a speaker-embedding model would be
//! more accurate, and it would reintroduce exactly the first-use download this
//! work removed. Two features and a deterministic 2-means is the honest trade,
//! and it is measured rather than assumed — see `scripts/diarize-bench.py`.
//!
//! It is a heuristic. It will be wrong in noisy rooms and with similar voices,
//! which is why the shell must keep offering one-click role correction.

use scribe_audio::{AudioBuffer, SpeechSpan};
use scribe_core::{Result, SpeakerId};

use crate::{Diarization, DiarizedTurn, Diarizer, TurnTakingDiarizer};

/// Two voices must differ by at least this much in log-pitch to be split.
///
/// `ln(1.15)` — roughly a 15% difference in fundamental frequency, about two
/// semitones. Below it, one voice is being divided by a clustering algorithm
/// that was told to find two clusters, which is the failure mode that makes a
/// dictation note alternate speakers arbitrarily.
const MIN_PITCH_SEPARATION: f32 = 0.14;

/// Pitch search range. Covers adult male through adult female speech with room
/// for the rise at the end of a question.
const MIN_F0_HZ: f32 = 60.0;
const MAX_F0_HZ: f32 = 400.0;

/// Autocorrelation is quadratic, so only a sample of frames per span is
/// measured. Pitch is stable within a turn; 24 frames is plenty for a median.
const MAX_FRAMES_PER_SPAN: usize = 24;
const FRAME_MS: u64 = 40;

/// A voiced frame must correlate with itself at the chosen lag at least this
/// well, or it is noise rather than speech.
const MIN_PERIODICITY: f32 = 0.30;

/// Splits spans into two speakers by the sound of the voice.
///
/// `Default` is derived: the fallback is `TurnTakingDiarizer`'s default, which is
/// what naming it in a manual impl would have said anyway.
#[derive(Debug, Clone, Copy, Default)]
pub struct AcousticDiarizer {
    /// Used when there is no audio to measure — see [`Diarizer::diarize_segments`].
    pub fallback: TurnTakingDiarizer,
}

/// What one span sounds like.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Voice {
    /// Median fundamental frequency, in Hz. `None` when nothing in the span was
    /// periodic enough to call pitched.
    f0_hz: Option<f32>,
    /// Zero crossings per second: a cheap proxy for brightness, which
    /// distinguishes voices when pitch is inconclusive.
    zcr: f32,
}

impl Diarizer for AcousticDiarizer {
    fn name(&self) -> &str {
        "acoustic-pitch-v1"
    }

    fn diarize(&self, audio: &AudioBuffer, spans: &[SpeechSpan]) -> Result<Diarization> {
        if spans.is_empty() {
            return Ok(Diarization::default());
        }

        let voices: Vec<Voice> = spans.iter().map(|span| measure(audio, span)).collect();

        // Spans with a usable pitch. Everything else is assigned afterwards.
        let pitched: Vec<(usize, f32)> = voices
            .iter()
            .enumerate()
            .filter_map(|(index, voice)| voice.f0_hz.map(|f0| (index, f0.ln())))
            .collect();

        if pitched.len() < 2 {
            // Nothing to compare. One voice is the truthful answer.
            return Ok(single_speaker(spans));
        }

        let (low, high) = two_means(&pitched);

        // A cluster split that small is the algorithm inventing a speaker out of
        // one person's ordinary variation in pitch.
        if high - low < MIN_PITCH_SEPARATION {
            return Ok(single_speaker(spans));
        }

        let boundary = (low + high) / 2.0;

        // Cluster 0 is the lower-pitched voice. Order the ids by pitch so the
        // answer does not depend on which span happened to come first.
        let mut turns = Vec::with_capacity(spans.len());
        for (index, span) in spans.iter().enumerate() {
            let speaker = match voices[index].f0_hz {
                Some(f0) => {
                    if f0.ln() <= boundary {
                        SpeakerId::new(0)
                    } else {
                        SpeakerId::new(1)
                    }
                }
                // No pitch here — a whisper, a cough. Keep whoever was talking:
                // a continuation is likelier than a change nobody heard.
                None => turns
                    .last()
                    .map(|turn: &DiarizedTurn| turn.speaker)
                    .unwrap_or_else(|| SpeakerId::new(0)),
            };
            turns.push(DiarizedTurn {
                start_ms: span.start_ms,
                end_ms: span.end_ms,
                speaker,
            });
        }

        Ok(Diarization { turns })
    }

    /// With no audio there is nothing to measure a voice from, so this falls
    /// back to the gaps — which is a real step down, and the caller should know
    /// it is asking for one.
    fn diarize_segments(&self, spans: &[SpeechSpan]) -> Result<Diarization> {
        self.fallback.diarize_segments(spans)
    }
}

fn single_speaker(spans: &[SpeechSpan]) -> Diarization {
    Diarization {
        turns: spans
            .iter()
            .map(|span| DiarizedTurn {
                start_ms: span.start_ms,
                end_ms: span.end_ms,
                speaker: SpeakerId::new(0),
            })
            .collect(),
    }
}

/// Measure a span's pitch and brightness.
fn measure(audio: &AudioBuffer, span: &SpeechSpan) -> Voice {
    let rate = audio.sample_rate;
    if rate == 0 {
        return Voice {
            f0_hz: None,
            zcr: 0.0,
        };
    }

    let first = ms_to_sample(span.start_ms, rate);
    let last = ms_to_sample(span.end_ms, rate).min(audio.samples.len());
    if first >= last {
        return Voice {
            f0_hz: None,
            zcr: 0.0,
        };
    }
    let samples = &audio.samples[first..last];

    Voice {
        f0_hz: median_f0(samples, rate),
        zcr: zero_crossing_rate(samples, rate),
    }
}

fn ms_to_sample(ms: u64, rate: u32) -> usize {
    ((ms as u128 * rate as u128) / 1000) as usize
}

/// Median fundamental frequency over evenly spaced frames of the span.
fn median_f0(samples: &[f32], rate: u32) -> Option<f32> {
    let frame_len = (rate as u64 * FRAME_MS / 1000).max(1) as usize;
    if samples.len() < frame_len {
        return None;
    }

    // Evenly spaced across the span rather than the first N, so a pause at the
    // start does not decide what the voice sounds like.
    let available = samples.len() - frame_len;
    let step = (available / MAX_FRAMES_PER_SPAN).max(1);

    let mut pitches: Vec<f32> = Vec::new();
    let mut offset = 0;
    while offset + frame_len <= samples.len() && pitches.len() < MAX_FRAMES_PER_SPAN {
        if let Some(f0) = frame_f0(&samples[offset..offset + frame_len], rate) {
            pitches.push(f0);
        }
        offset += step;
    }

    if pitches.is_empty() {
        return None;
    }
    pitches.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    Some(pitches[pitches.len() / 2])
}

/// Autocorrelation pitch estimate for one frame.
fn frame_f0(frame: &[f32], rate: u32) -> Option<f32> {
    let min_lag = (rate as f32 / MAX_F0_HZ) as usize;
    let max_lag = ((rate as f32 / MIN_F0_HZ) as usize).min(frame.len().saturating_sub(1));
    if max_lag <= min_lag {
        return None;
    }

    let energy: f32 = frame.iter().map(|s| s * s).sum();
    if energy <= f32::EPSILON {
        return None;
    }

    let mut best_lag = 0usize;
    let mut best = 0.0f32;
    for lag in min_lag..=max_lag {
        let mut sum = 0.0f32;
        for index in 0..(frame.len() - lag) {
            sum += frame[index] * frame[index + lag];
        }
        // Normalised so a loud frame does not win on volume alone.
        let score = sum / energy;
        if score > best {
            best = score;
            best_lag = lag;
        }
    }

    if best_lag == 0 || best < MIN_PERIODICITY {
        return None;
    }
    Some(rate as f32 / best_lag as f32)
}

fn zero_crossing_rate(samples: &[f32], rate: u32) -> f32 {
    if samples.len() < 2 || rate == 0 {
        return 0.0;
    }
    let crossings = samples
        .windows(2)
        .filter(|pair| (pair[0] >= 0.0) != (pair[1] >= 0.0))
        .count();
    let seconds = samples.len() as f32 / rate as f32;
    crossings as f32 / seconds
}

/// Deterministic 1-D k-means with two clusters, over log-pitch.
///
/// Initialised at the extremes and iterated a fixed number of times, so the same
/// recording always produces the same answer — a requirement of the trait, and
/// the reason there is no random restart here.
fn two_means(points: &[(usize, f32)]) -> (f32, f32) {
    let mut low = points
        .iter()
        .map(|(_, value)| *value)
        .fold(f32::INFINITY, f32::min);
    let mut high = points
        .iter()
        .map(|(_, value)| *value)
        .fold(f32::NEG_INFINITY, f32::max);

    if (high - low).abs() < f32::EPSILON {
        return (low, high);
    }

    for _ in 0..25 {
        let boundary = (low + high) / 2.0;
        let mut low_sum = 0.0;
        let mut low_count = 0usize;
        let mut high_sum = 0.0;
        let mut high_count = 0usize;

        for (_, value) in points {
            if *value <= boundary {
                low_sum += *value;
                low_count += 1;
            } else {
                high_sum += *value;
                high_count += 1;
            }
        }

        // An empty cluster means the split has converged.
        if low_count == 0 || high_count == 0 {
            break;
        }
        let next_low = low_sum / low_count as f32;
        let next_high = high_sum / high_count as f32;
        if (next_low - low).abs() < 1e-4 && (next_high - high).abs() < 1e-4 {
            low = next_low;
            high = next_high;
            break;
        }
        low = next_low;
        high = next_high;
    }

    (low, high)
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

    /// Two voices at different pitches, back to back with no silence between
    /// them — the case silence-based diarisation cannot do at all.
    #[test]
    fn separates_two_pitches_with_no_gaps_between_them() {
        let rate = 16_000;
        let mut samples = Vec::new();
        // A low voice, then a high one, then the low one again. Adjacent spans:
        // every gap is zero, so there is nothing for turn-taking to read.
        samples.extend(tone(110.0, 1500, rate));
        samples.extend(tone(220.0, 1500, rate));
        samples.extend(tone(115.0, 1500, rate));

        let audio = AudioBuffer::new(samples, rate);
        let spans = vec![
            SpeechSpan {
                start_ms: 0,
                end_ms: 1500,
            },
            SpeechSpan {
                start_ms: 1500,
                end_ms: 3000,
            },
            SpeechSpan {
                start_ms: 3000,
                end_ms: 4500,
            },
        ];

        let diarization = AcousticDiarizer::default().diarize(&audio, &spans).unwrap();
        assert_eq!(diarization.turns.len(), 3);
        assert_eq!(diarization.turns[0].speaker, SpeakerId::new(0));
        assert_eq!(diarization.turns[1].speaker, SpeakerId::new(1));
        assert_eq!(diarization.turns[2].speaker, SpeakerId::new(0));
        assert_eq!(diarization.distinct_speakers().len(), 2);
    }

    /// One person, whose pitch drifts a little. Inventing a second speaker here
    /// is what makes a dictated note alternate arbitrarily.
    #[test]
    fn one_voice_stays_one_speaker() {
        let rate = 16_000;
        let mut samples = Vec::new();
        for freq in [118.0, 124.0, 121.0, 126.0] {
            samples.extend(tone(freq, 1200, rate));
        }

        let audio = AudioBuffer::new(samples, rate);
        let spans: Vec<SpeechSpan> = (0..4)
            .map(|index| SpeechSpan {
                start_ms: index * 1200,
                end_ms: index * 1200 + 1200,
            })
            .collect();

        let diarization = AcousticDiarizer::default().diarize(&audio, &spans).unwrap();
        assert_eq!(
            diarization.distinct_speakers().len(),
            1,
            "a 7% pitch drift is one voice, not two"
        );
    }

    #[test]
    fn no_spans_is_no_turns() {
        let audio = AudioBuffer::new(vec![0.0; 16_000], 16_000);
        let diarization = AcousticDiarizer::default().diarize(&audio, &[]).unwrap();
        assert!(diarization.turns.is_empty());
    }

    /// Without audio it must still answer, using the gaps — worse, and known.
    #[test]
    fn falls_back_to_gaps_when_there_is_no_audio() {
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
        let diarization = AcousticDiarizer::default()
            .diarize_segments(&spans)
            .unwrap();
        assert_eq!(diarization.distinct_speakers().len(), 2);
    }

    #[test]
    fn pitch_estimate_is_close_to_the_tone_it_was_given() {
        let rate = 16_000;
        let samples = tone(150.0, 500, rate);
        let f0 = median_f0(&samples, rate).expect("a pure tone is pitched");
        assert!((f0 - 150.0).abs() < 8.0, "expected ~150 Hz, got {f0}");
    }
}
