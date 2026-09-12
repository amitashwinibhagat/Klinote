//! Note generation.
//!
//! Two layers, deliberately separated:
//!
//! - [`templates::TemplateLibrary`] — loads and validates the note templates
//!   that define a discipline's structure.
//! - [`generator::NoteGenerator`] — turns an encounter + transcript + template
//!   into a [`scribe_core::ClinicalNote`].
//!
//! The shipped generator is [`rule_based::RuleBasedGenerator`]: deterministic,
//! offline, no model, auditable. A model-backed generator (Apple Foundation
//! Models / a local llama.cpp model) implements the same trait and can be
//! swapped in without touching callers — see `docs/engineering/ARCHITECTURE.md`.

pub mod generator;
pub mod rule_based;
pub mod templates;

pub use generator::{GenerationRequest, NoteGenerator};
pub use rule_based::RuleBasedGenerator;
pub use templates::TemplateLibrary;
