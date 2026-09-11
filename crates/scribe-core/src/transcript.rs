use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::{Result, ScribeError};
use crate::ids::{EncounterId, SegmentId, SpeakerId};

/// The role a speaker plays in the encounter. Roles — not identities — are
/// what the note generator reasons about.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeakerRole {
    Clinician,
    Patient,
    Caregiver,
    Other,
}

impl SpeakerRole {
    /// Parse the role prefixes accepted by `parse_transcript_text`.
    pub fn from_prefix(prefix: &str) -> Option<Self> {
        match prefix.trim().to_ascii_lowercase().as_str() {
            "clinician" | "doctor" | "dr" | "nurse" | "vet" | "therapist" | "provider" => {
                Some(SpeakerRole::Clinician)
            }
            "patient" | "pt" | "client" | "owner" => Some(SpeakerRole::Patient),
            "caregiver" | "carer" | "parent" | "guardian" | "spouse" => {
                Some(SpeakerRole::Caregiver)
            }
            "other" | "interpreter" | "student" => Some(SpeakerRole::Other),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            SpeakerRole::Clinician => "clinician",
            SpeakerRole::Patient => "patient",
            SpeakerRole::Caregiver => "caregiver",
            SpeakerRole::Other => "other",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Speaker {
    pub id: SpeakerId,
    pub role: SpeakerRole,
    pub label: Option<String>,
}

impl Speaker {
    pub fn new(id: SpeakerId, role: SpeakerRole) -> Self {
        Self {
            id,
            role,
            label: None,
        }
    }
}

/// One diarised, transcribed span of speech.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub id: SegmentId,
    pub speaker: SpeakerId,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub confidence: Option<f32>,
}

impl Segment {
    pub fn new(speaker: SpeakerId, start_ms: u64, end_ms: u64, text: impl Into<String>) -> Self {
        Self {
            id: SegmentId::new(),
            speaker,
            start_ms,
            end_ms,
            text: text.into(),
            confidence: None,
        }
    }

    pub fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms)
    }
}

/// The full transcript of an encounter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transcript {
    pub encounter_id: EncounterId,
    pub speakers: Vec<Speaker>,
    pub segments: Vec<Segment>,
    pub language: String,
    /// Which engine produced this (`"mock"`, `"whisper-large-v3-turbo"`, `"apple-speechanalyzer"`).
    pub engine: String,
    pub created_at: DateTime<Utc>,
    /// True when the text came from a human-supplied transcript rather than ASR.
    #[serde(default)]
    pub human_supplied: bool,
}

/// A run of consecutive segments from one speaker — the unit the note
/// generator routes into sections.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Utterance {
    pub speaker: SpeakerId,
    pub role: SpeakerRole,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub segment_ids: Vec<SegmentId>,
}

impl Transcript {
    pub fn new(encounter_id: EncounterId, engine: impl Into<String>) -> Self {
        Self {
            encounter_id,
            speakers: Vec::new(),
            segments: Vec::new(),
            language: "en".to_owned(),
            engine: engine.into(),
            created_at: Utc::now(),
            human_supplied: false,
        }
    }

    pub fn push_speaker(&mut self, speaker: Speaker) {
        if !self.speakers.iter().any(|s| s.id == speaker.id) {
            self.speakers.push(speaker);
        }
    }

    pub fn push_segment(&mut self, segment: Segment) {
        self.segments.push(segment);
    }

    pub fn role_of(&self, speaker: SpeakerId) -> SpeakerRole {
        self.speakers
            .iter()
            .find(|s| s.id == speaker)
            .map(|s| s.role)
            .unwrap_or(SpeakerRole::Other)
    }

    pub fn full_text(&self) -> String {
        self.segments
            .iter()
            .map(|s| s.text.trim())
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn text_for_role(&self, role: SpeakerRole) -> String {
        self.segments
            .iter()
            .filter(|s| self.role_of(s.speaker) == role)
            .map(|s| s.text.trim())
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn word_count(&self) -> usize {
        self.full_text().split_whitespace().count()
    }

    pub fn duration_ms(&self) -> u64 {
        self.segments
            .iter()
            .map(|s| s.end_ms)
            .max()
            .unwrap_or_default()
    }

    /// Merge consecutive segments from the same speaker into utterances.
    ///
    /// Segments are assumed to be in chronological order; callers that build
    /// transcripts out of order should sort first.
    pub fn utterances(&self) -> Vec<Utterance> {
        let mut out: Vec<Utterance> = Vec::new();

        for segment in &self.segments {
            let role = self.role_of(segment.speaker);
            match out.last_mut() {
                Some(last) if last.speaker == segment.speaker => {
                    if !last.text.is_empty() {
                        last.text.push(' ');
                    }
                    last.text.push_str(segment.text.trim());
                    last.end_ms = segment.end_ms;
                    last.segment_ids.push(segment.id);
                }
                _ => out.push(Utterance {
                    speaker: segment.speaker,
                    role,
                    start_ms: segment.start_ms,
                    end_ms: segment.end_ms,
                    text: segment.text.trim().to_owned(),
                    segment_ids: vec![segment.id],
                }),
            }
        }

        out
    }
}

/// Parse a plain-text transcript of the form:
///
/// ```text
/// CLINICIAN: Good morning, what brings you in today?
/// PATIENT: I've had a sore throat for four days.
/// [00:42] CLINICIAN: Any fever?
/// ```
///
/// A timestamp prefix (`[mm:ss]` or `[hh:mm:ss]`) is optional. Lines without a
/// recognised role prefix continue the previous speaker, so wrapped text and
/// pasted ASR output both work.
///
/// This is the bridge that makes the concierge validation loop possible:
/// a human transcript in, a structured note out, with no model involved.
pub fn parse_transcript_text(
    text: &str,
    encounter_id: EncounterId,
    language: &str,
) -> Result<Transcript> {
    let mut transcript = Transcript::new(encounter_id, "human-transcript");
    transcript.language = language.to_owned();
    transcript.human_supplied = true;

    // Assign stable speaker ids in order of first appearance.
    let speaker_for_role = |transcript: &mut Transcript, role: SpeakerRole| -> SpeakerId {
        if let Some(existing) = transcript.speakers.iter().find(|s| s.role == role) {
            return existing.id;
        }
        let id = match role {
            SpeakerRole::Clinician => SpeakerId::CLINICIAN,
            SpeakerRole::Patient => SpeakerId::PATIENT,
            other => {
                let next = transcript.speakers.len() as u32;
                // Avoid colliding with the two well-known ids.
                let candidate = SpeakerId::new(next.max(2));
                let _ = other;
                candidate
            }
        };
        transcript.push_speaker(Speaker::new(id, role));
        id
    };

    let mut cursor_ms: u64 = 0;
    let mut last_role: Option<SpeakerRole> = None;
    let mut saw_any = false;

    for raw_line in text.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let (timestamp_ms, rest) = split_timestamp(line);
        let (role, body) = split_role(rest);

        let role = match role {
            Some(role) => role,
            None => match last_role {
                Some(previous) => previous,
                None => {
                    // Untagged leading text: treat as clinician dictation, the
                    // common case when a clinician pastes free text.
                    SpeakerRole::Clinician
                }
            },
        };
        last_role = Some(role);

        if body.trim().is_empty() {
            continue;
        }

        let start_ms = timestamp_ms.unwrap_or(cursor_ms);
        // 2.5 words/second is a reasonable speaking-rate estimate when the
        // source has no timings of its own.
        let est_ms = ((body.split_whitespace().count().max(1) as u64) * 400).min(30_000);
        let end_ms = start_ms + est_ms;
        cursor_ms = end_ms + 200;

        let speaker = speaker_for_role(&mut transcript, role);
        transcript.push_segment(Segment::new(speaker, start_ms, end_ms, body.trim()));
        saw_any = true;
    }

    if !saw_any {
        return Err(ScribeError::InvalidInput(
            "transcript contained no usable lines".to_owned(),
        ));
    }

    Ok(transcript)
}

/// Returns `(timestamp_ms, remainder)`.
fn split_timestamp(line: &str) -> (Option<u64>, &str) {
    let trimmed = line.trim_start();
    if !trimmed.starts_with('[') {
        return (None, line);
    }
    let Some(close) = trimmed.find(']') else {
        return (None, line);
    };
    let inner = &trimmed[1..close];
    match parse_timestamp(inner) {
        Some(ms) => (Some(ms), trimmed[close + 1..].trim_start()),
        None => (None, line),
    }
}

fn parse_timestamp(value: &str) -> Option<u64> {
    let parts: Vec<&str> = value.split(':').collect();
    let (h, m, s) = match parts.as_slice() {
        [m, s] => (0u64, m.parse::<u64>().ok()?, s.parse::<u64>().ok()?),
        [h, m, s] => (
            h.parse::<u64>().ok()?,
            m.parse::<u64>().ok()?,
            s.parse::<u64>().ok()?,
        ),
        _ => return None,
    };
    Some((h * 3600 + m * 60 + s) * 1000)
}

/// Returns `(role, body)` when the line starts with a `ROLE:` prefix.
fn split_role(line: &str) -> (Option<SpeakerRole>, &str) {
    let Some(colon) = line.find(':') else {
        return (None, line);
    };
    let (head, tail) = line.split_at(colon);
    // Guard against URLs and clock times being mistaken for role prefixes.
    if head.len() > 12
        || head.trim().contains(char::is_whitespace) && head.split_whitespace().count() > 2
    {
        return (None, line);
    }
    match SpeakerRole::from_prefix(head) {
        Some(role) => (Some(role), tail[1..].trim_start()),
        None => (None, line),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_roles_and_timestamps() {
        let text = "\
CLINICIAN: Good morning, what brings you in today?
PATIENT: I've had a sore throat for four days.
[00:42] CLINICIAN: Any fever?
continued detail from the patient
patient: no fever
";
        let t = parse_transcript_text(text, EncounterId::new(), "en").unwrap();
        assert_eq!(t.segments.len(), 5);
        assert_eq!(t.role_of(t.segments[0].speaker), SpeakerRole::Clinician);
        assert_eq!(t.role_of(t.segments[1].speaker), SpeakerRole::Patient);
        assert_eq!(t.segments[2].start_ms, 42_000);
        // Untagged line continues the previous speaker (the clinician).
        assert_eq!(t.role_of(t.segments[3].speaker), SpeakerRole::Clinician);
        assert_eq!(t.role_of(t.segments[4].speaker), SpeakerRole::Patient);
        assert_eq!(t.segments[4].start_ms, t.segments[3].end_ms + 200);
    }

    #[test]
    fn untagged_text_is_treated_as_clinician_dictation() {
        let t = parse_transcript_text(
            "Chest clear on auscultation. Plan: amoxicillin 500mg tds.",
            EncounterId::new(),
            "en",
        )
        .unwrap();
        assert_eq!(t.segments.len(), 1);
        assert_eq!(t.role_of(t.segments[0].speaker), SpeakerRole::Clinician);
    }

    #[test]
    fn utterances_merge_consecutive_same_speaker() {
        let mut t = Transcript::new(EncounterId::new(), "test");
        t.push_speaker(Speaker::new(SpeakerId::CLINICIAN, SpeakerRole::Clinician));
        t.push_segment(Segment::new(SpeakerId::CLINICIAN, 0, 1000, "one"));
        t.push_segment(Segment::new(SpeakerId::CLINICIAN, 1000, 2000, "two"));
        t.push_segment(Segment::new(SpeakerId::PATIENT, 2000, 3000, "three"));
        let u = t.utterances();
        assert_eq!(u.len(), 2);
        assert_eq!(u[0].text, "one two");
        assert_eq!(u[0].segment_ids.len(), 2);
    }
}
