use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::ids::{EncounterId, NoteId, SegmentId, TemplateId};

/// Where a note sits in the human review workflow. Only a human moves a note
/// out of `Draft`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewState {
    Draft,
    Edited,
    Approved,
}

impl ReviewState {
    pub fn as_str(&self) -> &'static str {
        match self {
            ReviewState::Draft => "draft",
            ReviewState::Edited => "edited",
            ReviewState::Approved => "approved",
        }
    }
}

/// One sentence of a note, with the transcript segments it came from.
///
/// Sentence-level evidence is what makes the note checkable rather than
/// merely plausible: a clinician can select any sentence and see the exact
/// words that produced it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteSentence {
    pub text: String,
    #[serde(default)]
    pub evidence: Vec<SegmentId>,
    /// True when the routing had more than one plausible home for this
    /// sentence. Surfaced to the reviewer rather than silently decided.
    #[serde(default)]
    pub ambiguous: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteSection {
    pub key: String,
    pub title: String,
    pub body: String,
    /// Transcript segments the body was derived from, so a clinician can audit
    /// any sentence back to what was actually said.
    #[serde(default)]
    pub evidence: Vec<SegmentId>,
    /// The same content as `body`, split into sentences that each carry their
    /// own evidence.
    #[serde(default)]
    pub sentences: Vec<NoteSentence>,
    pub complete: bool,
}

impl NoteSection {
    pub fn empty(spec_key: &str, title: &str) -> Self {
        Self {
            key: spec_key.to_owned(),
            title: title.to_owned(),
            body: String::new(),
            evidence: Vec::new(),
            sentences: Vec::new(),
            complete: false,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.body.trim().is_empty()
    }
}

/// Text the generator could not confidently route. Kept visible rather than
/// silently dropped — an unfiled sentence is a clinical risk, not noise.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnassignedItem {
    pub text: String,
    #[serde(default)]
    pub speaker_role: String,
    #[serde(default)]
    pub evidence: Vec<SegmentId>,
}

/// The generated note.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClinicalNote {
    pub id: NoteId,
    pub encounter_id: EncounterId,
    pub template_id: TemplateId,
    pub sections: Vec<NoteSection>,
    #[serde(default)]
    pub unassigned: Vec<UnassignedItem>,
    pub generated_at: DateTime<Utc>,
    /// Generator identity, e.g. `rule-based-v1` or `afm3-core-advanced`.
    pub engine: String,
    pub review_state: ReviewState,
    /// Required section keys that came back empty.
    #[serde(default)]
    pub missing_required: Vec<String>,
    /// True when a machine produced this without human editing.
    #[serde(default)]
    pub machine_generated: bool,
}

impl ClinicalNote {
    pub fn section(&self, key: &str) -> Option<&NoteSection> {
        self.sections.iter().find(|s| s.key == key)
    }

    /// Fraction of sections that carry content, 0.0–1.0.
    ///
    /// Emptiness in *required* sections is reported separately via
    /// `missing_required`, which is the signal that actually blocks signing.
    pub fn completeness(&self) -> f32 {
        let total = self.sections.len();
        if total == 0 {
            return 0.0;
        }
        let filled = self.sections.iter().filter(|s| !s.is_empty()).count();
        filled as f32 / total as f32
    }

    pub fn required_missing(&self) -> bool {
        !self.missing_required.is_empty()
    }

    /// Clinician-facing markdown. This is what the concierge loop emails out.
    pub fn to_markdown(&self) -> String {
        use std::fmt::Write as _;
        let mut out = String::new();

        let _ = writeln!(out, "# Clinical Note — {}", self.template_id);
        let _ = writeln!(out);
        let _ = writeln!(out, "- **Encounter:** `{}`", self.encounter_id);
        let _ = writeln!(out, "- **Generated:** {}", self.generated_at.to_rfc3339());
        let _ = writeln!(out, "- **Engine:** {}", self.engine);
        let _ = writeln!(out, "- **Review state:** {}", self.review_state.as_str());
        let _ = writeln!(
            out,
            "- **Completeness:** {:.0}%",
            (self.completeness() * 100.0).round()
        );
        let _ = writeln!(out);

        for section in &self.sections {
            let _ = writeln!(out, "## {}", section.title);
            if section.is_empty() {
                let _ = writeln!(out, "_Not documented._");
            } else {
                let _ = writeln!(out, "{}", section.body.trim());
            }
            let _ = writeln!(out);
        }

        if !self.missing_required.is_empty() {
            let _ = writeln!(out, "---");
            let _ = writeln!(out);
            let _ = writeln!(out, "### ⚠ Missing required sections");
            for key in &self.missing_required {
                let _ = writeln!(out, "- `{key}`");
            }
            let _ = writeln!(out);
        }

        if !self.unassigned.is_empty() {
            let _ = writeln!(out, "---");
            let _ = writeln!(out);
            let _ = writeln!(out, "### Unfiled statements (review before signing)");
            for item in &self.unassigned {
                let _ = writeln!(out, "- {}: {}", item.speaker_role, item.text.trim());
            }
            let _ = writeln!(out);
        }

        let _ = writeln!(out, "---");
        let _ = writeln!(
            out,
            "_Draft generated on-device. Clinician review required before entry into the medical record._"
        );

        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note_with(sections: Vec<NoteSection>) -> ClinicalNote {
        ClinicalNote {
            id: NoteId::new(),
            encounter_id: EncounterId::new(),
            template_id: TemplateId::new("soap"),
            sections,
            unassigned: Vec::new(),
            generated_at: Utc::now(),
            engine: "test".to_owned(),
            review_state: ReviewState::Draft,
            missing_required: Vec::new(),
            machine_generated: true,
        }
    }

    fn filled(key: &str, body: &str) -> NoteSection {
        NoteSection {
            key: key.to_owned(),
            title: key.to_owned(),
            body: body.to_owned(),
            evidence: Vec::new(),
            sentences: Vec::new(),
            complete: true,
        }
    }

    #[test]
    fn completeness_counts_filled_sections() {
        let n = note_with(vec![filled("s", "text"), NoteSection::empty("o", "o")]);
        assert!((n.completeness() - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn markdown_flags_missing_and_unfiled() {
        let mut n = note_with(vec![
            filled("s", "sore throat"),
            NoteSection::empty("o", "objective"),
        ]);
        n.missing_required = vec!["o".to_owned()];
        n.unassigned = vec![UnassignedItem {
            text: "see you next week".to_owned(),
            speaker_role: "clinician".to_owned(),
            evidence: Vec::new(),
        }];
        let md = n.to_markdown();
        assert!(md.contains("Missing required sections"));
        assert!(md.contains("Unfiled statements"));
        assert!(md.contains("Not documented."));
    }
}
