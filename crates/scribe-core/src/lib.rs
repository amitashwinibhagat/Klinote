//! Domain model for Local Clinical Scribe.
//!
//! This crate is deliberately dependency-light and free of any platform or
//! model-runtime concerns. It is the shared vocabulary used by the audio,
//! ASR, diarisation, note-generation and storage layers, and — via
//! `scribe-ffi` — by the Swift shell.
//!
//! ## Privacy invariant
//!
//! No type in this crate may hold direct patient identifiers. `Encounter`
//! carries an opaque `patient_ref` that the calling application is
//! responsible for minting and for keeping the mapping out of this crate's
//! data. See `docs/compliance/PRIVACY.md`.

pub mod encounter;
pub mod error;
pub mod formulary;
pub mod ids;
pub mod note;
pub mod register;
pub mod support;
pub mod template;
pub mod transcript;

pub use encounter::{Discipline, Encounter};
pub use error::{Result, ScribeError};
pub use formulary::{NameCheck, suggest as suggest_names};
pub use ids::{EncounterId, NoteId, SegmentId, SpeakerId, TemplateId};
pub use note::{
    ClinicalNote, NoteSection, NoteSentence, ReviewState, Support, UnassignedItem, Wording,
};
pub use template::{Audience, RenderKind, SectionSpec, Template, TemplateFamily};
pub use transcript::{Segment, Speaker, SpeakerRole, Transcript, Utterance, parse_transcript_text};

/// Version of the domain model / FFI contract. Bump on breaking changes.
///
/// 0.2.0 — `scribe_note_from_audio` was replaced by `scribe_note_from_segments`.
/// The shell does speech recognition now, so the old entry point (which fell
/// back to synthetic `MockAsrEngine` text when handed no model) is gone.
pub const SCHEMA_VERSION: &str = "0.2.0";
