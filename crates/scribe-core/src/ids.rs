use std::fmt;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

macro_rules! uuid_id {
    ($name:ident, $doc:literal) => {
        #[doc = $doc]
        #[derive(
            Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize,
        )]
        #[serde(transparent)]
        pub struct $name(pub Uuid);

        impl $name {
            pub fn new() -> Self {
                Self(Uuid::new_v4())
            }

            pub fn as_uuid(&self) -> Uuid {
                self.0
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                write!(f, "{}", self.0)
            }
        }

        impl std::str::FromStr for $name {
            type Err = uuid::Error;

            fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
                Ok(Self(Uuid::parse_str(s)?))
            }
        }
    };
}

uuid_id!(
    EncounterId,
    "Identifies a single clinical encounter (one consultation)."
);
uuid_id!(
    NoteId,
    "Identifies one generated note (a note may be regenerated; each is new)."
);
uuid_id!(
    SegmentId,
    "Identifies one transcript segment so a note section can cite its evidence."
);

/// Diarisation label. `0` is reserved for the clinician so that a
/// single-speaker fallback still produces a sensible role.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SpeakerId(pub u32);

impl SpeakerId {
    pub const CLINICIAN: SpeakerId = SpeakerId(0);
    pub const PATIENT: SpeakerId = SpeakerId(1);

    pub const fn new(n: u32) -> Self {
        Self(n)
    }
}

impl fmt::Display for SpeakerId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "S{}", self.0)
    }
}

/// Stable, human-readable template identifier (`"soap"`, `"physiotherapy"`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TemplateId(pub String);

impl TemplateId {
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for TemplateId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl From<&str> for TemplateId {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

impl From<String> for TemplateId {
    fn from(value: String) -> Self {
        Self(value)
    }
}
