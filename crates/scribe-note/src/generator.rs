use scribe_core::{ClinicalNote, Encounter, Result, Template, Transcript};

/// Everything a generator needs. Borrowed so generators stay allocation-light
/// and can run under a tight latency budget.
pub struct GenerationRequest<'a> {
    pub encounter: &'a Encounter,
    pub transcript: &'a Transcript,
    pub template: &'a Template,
}

/// A note generator.
///
/// Implementations must be deterministic given the same request, must never
/// make a network call, and must never silently drop transcript content —
/// anything not confidently filed goes into `ClinicalNote::unassigned`.
pub trait NoteGenerator {
    /// Stable identity recorded on the note, e.g. `rule-based-v1`.
    fn name(&self) -> &str;

    fn generate(&self, request: &GenerationRequest<'_>) -> Result<ClinicalNote>;
}
