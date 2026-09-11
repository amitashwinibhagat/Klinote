use serde::{Deserialize, Serialize};

use crate::error::{Result, ScribeError};
use crate::ids::TemplateId;

/// One section of a note template.
///
/// `cues` are the vocabulary the rule-based generator uses to route transcript
/// sentences into this section. They are intentionally editable in the TOML so
/// a clinician can tune routing per practice without touching code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectionSpec {
    pub key: String,
    pub title: String,
    #[serde(default)]
    pub guidance: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub cues: Vec<String>,
}

/// How a generated document is laid out when it is put on the clipboard.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RenderKind {
    /// A clinical note: section titles and bodies.
    #[default]
    Sections,
    /// A letter to a colleague.
    Letter,
}

/// What the clinician is producing from the consult.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TemplateFamily {
    /// The note itself.
    #[default]
    Note,
    /// Another document the consult already owes: a referral letter, a
    /// patient's copy. Derived from the same transcript, never a second
    /// recording.
    Document,
}

/// A note template: the contract between a discipline and the generated note.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Template {
    pub id: TemplateId,
    pub name: String,
    pub discipline: String,
    #[serde(default = "default_version")]
    pub version: String,
    #[serde(default)]
    pub description: String,
    /// Register instruction for the language model, e.g. "plain language for
    /// the patient". Empty means clinical shorthand.
    #[serde(default)]
    pub voice: String,
    #[serde(default)]
    pub family: TemplateFamily,
    #[serde(default)]
    pub render: RenderKind,
    pub sections: Vec<SectionSpec>,
}

fn default_version() -> String {
    "1".to_owned()
}

impl Template {
    pub fn section(&self, key: &str) -> Option<&SectionSpec> {
        self.sections.iter().find(|s| s.key == key)
    }

    pub fn required_keys(&self) -> Vec<&str> {
        self.sections
            .iter()
            .filter(|s| s.required)
            .map(|s| s.key.as_str())
            .collect()
    }

    /// Structural validation. A template that fails this must never ship.
    pub fn validate(&self) -> Result<()> {
        let fail = |reason: &str| -> ScribeError {
            ScribeError::InvalidTemplate {
                id: self.id.to_string(),
                reason: reason.to_owned(),
            }
        };

        if self.id.as_str().trim().is_empty() {
            return Err(fail("id is empty"));
        }
        if self.sections.is_empty() {
            return Err(fail("has no sections"));
        }

        let mut seen = std::collections::BTreeSet::new();
        for section in &self.sections {
            if section.key.trim().is_empty() {
                return Err(fail("section with empty key"));
            }
            if !seen.insert(section.key.as_str()) {
                return Err(fail(&format!("duplicate section key '{}'", section.key)));
            }
            if section.title.trim().is_empty() {
                return Err(fail(&format!("section '{}' has no title", section.key)));
            }
        }

        if self.required_keys().is_empty() {
            return Err(fail("has no required sections"));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn template_with(sections: Vec<SectionSpec>) -> Template {
        Template {
            id: TemplateId::new("t"),
            name: "T".to_owned(),
            discipline: "general_practice".to_owned(),
            version: "1".to_owned(),
            description: String::new(),
            voice: String::new(),
            family: TemplateFamily::Note,
            render: RenderKind::Sections,
            sections,
        }
    }

    fn section(key: &str, required: bool) -> SectionSpec {
        SectionSpec {
            key: key.to_owned(),
            title: key.to_owned(),
            guidance: String::new(),
            required,
            cues: Vec::new(),
        }
    }

    #[test]
    fn rejects_duplicate_keys() {
        let t = template_with(vec![section("a", true), section("a", false)]);
        assert!(t.validate().is_err());
    }

    #[test]
    fn rejects_template_without_required_sections() {
        let t = template_with(vec![section("a", false)]);
        assert!(t.validate().is_err());
    }

    #[test]
    fn accepts_well_formed_template() {
        let t = template_with(vec![section("a", true), section("b", false)]);
        assert!(t.validate().is_ok());
    }
}
