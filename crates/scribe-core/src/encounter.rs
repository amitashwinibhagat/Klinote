use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::ids::{EncounterId, TemplateId};

/// Discipline selects the default note template and terminology handling.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Discipline {
    GeneralPractice,
    Physiotherapy,
    Psychology,
    Dentistry,
    Veterinary,
    Nursing,
    Other(String),
}

impl Discipline {
    pub fn as_str(&self) -> &str {
        match self {
            Discipline::GeneralPractice => "general_practice",
            Discipline::Physiotherapy => "physiotherapy",
            Discipline::Psychology => "psychology",
            Discipline::Dentistry => "dentistry",
            Discipline::Veterinary => "veterinary",
            Discipline::Nursing => "nursing",
            Discipline::Other(other) => other,
        }
    }

    /// Best-effort parse from the discipline key used in config and templates.
    pub fn from_key(key: &str) -> Self {
        match key.trim().to_ascii_lowercase().as_str() {
            "general_practice" | "gp" | "gp_medicine" => Discipline::GeneralPractice,
            "physiotherapy" | "physio" | "pt" => Discipline::Physiotherapy,
            "psychology" | "psych" | "therapy" => Discipline::Psychology,
            "dentistry" | "dental" | "dentist" => Discipline::Dentistry,
            "veterinary" | "vet" => Discipline::Veterinary,
            "nursing" | "nurse" => Discipline::Nursing,
            other => Discipline::Other(other.to_owned()),
        }
    }

    /// Default template used when the caller does not pin one.
    pub fn default_template(&self) -> TemplateId {
        match self {
            Discipline::GeneralPractice => TemplateId::new("soap"),
            Discipline::Physiotherapy => TemplateId::new("physiotherapy"),
            Discipline::Psychology => TemplateId::new("psychology"),
            Discipline::Dentistry => TemplateId::new("dentistry"),
            Discipline::Veterinary => TemplateId::new("veterinary"),
            Discipline::Nursing => TemplateId::new("soap"),
            Discipline::Other(_) => TemplateId::new("soap"),
        }
    }
}

/// A single consultation.
///
/// `patient_ref` is an opaque, pseudonymous handle. It must never be a name,
/// MRN, NHS number, date of birth or any other direct identifier — the shell
/// owns the mapping and keeps it out of the Rust core.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Encounter {
    pub id: EncounterId,
    pub patient_ref: String,
    pub clinician_ref: Option<String>,
    pub discipline: Discipline,
    pub template_id: TemplateId,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub language: Option<String>,
    pub site_ref: Option<String>,
}

impl Encounter {
    pub fn new(patient_ref: impl Into<String>, discipline: Discipline) -> Self {
        let template_id = discipline.default_template();
        Self {
            id: EncounterId::new(),
            patient_ref: patient_ref.into(),
            clinician_ref: None,
            discipline,
            template_id,
            started_at: Utc::now(),
            ended_at: None,
            language: None,
            site_ref: None,
        }
    }

    pub fn with_template(mut self, template_id: impl Into<TemplateId>) -> Self {
        self.template_id = template_id.into();
        self
    }

    pub fn with_clinician(mut self, clinician_ref: impl Into<String>) -> Self {
        self.clinician_ref = Some(clinician_ref.into());
        self
    }

    pub fn duration_ms(&self) -> Option<i64> {
        self.ended_at
            .map(|end| (end - self.started_at).num_milliseconds())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discipline_keys_round_trip() {
        for key in [
            "general_practice",
            "physiotherapy",
            "psychology",
            "dentistry",
            "veterinary",
            "nursing",
        ] {
            assert_eq!(Discipline::from_key(key).as_str(), key);
        }
    }

    #[test]
    fn discipline_defaults_to_a_template() {
        assert_eq!(
            Discipline::Physiotherapy.default_template().as_str(),
            "physiotherapy"
        );
        assert_eq!(
            Discipline::from_key("gp").default_template().as_str(),
            "soap"
        );
    }
}
