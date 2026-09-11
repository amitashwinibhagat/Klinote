//! C ABI exposing the engine to the Swift shell.
//!
//! ## Why a hand-written C ABI and not UniFFI (yet)
//!
//! The Swift boundary is small and JSON-shaped: list templates, generate a
//! note from a transcript, render a note. A plain C ABI with a JSON payload is
//! trivial to call from Swift today, has no codegen step in the build, and
//! keeps the surface auditable — which matters for a clinical product.
//!
//! When the boundary grows state (streaming sessions, callbacks, a model
//! handle), migrate to `uniffi` (0.32+) and delete this crate's JSON
//! envelopes. The domain types are already serde-friendly, so the migration is
//! mechanical. See `docs/engineering/ADR/0001-rust-core-swift-shell.md`.
//!
//! ## Contract
//!
//! - Every function returning `*mut c_char` returns a heap-allocated,
//!   NUL-terminated UTF-8 JSON string that the caller **must** free with
//!   [`scribe_string_free`].
//! - Every payload function returns an envelope:
//!   `{"ok": true, ...}` on success, `{"ok": false, "error": "..."}` on
//!   failure. Failures never panic across the boundary.
//! - Input pointers must be valid NUL-terminated UTF-8 or null.

use std::ffi::{CStr, CString, c_char};

use scribe_core::{ClinicalNote, Discipline, Encounter, SCHEMA_VERSION, Transcript};
use scribe_note::TemplateLibrary;
use scribe_pipeline::ScribePipeline;
use serde::Deserialize;
use serde_json::{Value, json};

/// Version of this FFI contract, for the Swift side to assert against.
#[unsafe(no_mangle)]
pub extern "C" fn scribe_schema_version() -> *mut c_char {
    into_c_string(SCHEMA_VERSION)
}

/// JSON: `{"ok":true,"templates":[{...}]}`.
#[unsafe(no_mangle)]
pub extern "C" fn scribe_list_templates() -> *mut c_char {
    let result = TemplateLibrary::builtin().map(|library| {
        let templates: Vec<Value> = library
            .iter()
            .map(|template| {
                json!({
                    "id": template.id.as_str(),
                    "name": template.name,
                    "discipline": template.discipline,
                    "version": template.version,
                    "description": template.description,
                    "sections": template.sections.iter().map(|section| json!({
                        "key": section.key,
                        "title": section.title,
                        "guidance": section.guidance,
                        "required": section.required,
                    })).collect::<Vec<_>>(),
                })
            })
            .collect();
        json!({ "ok": true, "templates": templates })
    });

    into_c_string(
        &result
            .unwrap_or_else(|err| error_envelope(err.to_string()))
            .to_string(),
    )
}

#[derive(Debug, Deserialize)]
struct NoteRequest {
    /// Optional full encounter. When omitted, one is synthesised from
    /// `template_id` so the shell can render a preview before an encounter
    /// record exists.
    #[serde(default)]
    encounter: Option<Encounter>,
    #[serde(default)]
    template_id: Option<String>,
    transcript: Transcript,
}

/// Input JSON: `{"encounter":{...},"transcript":{...}}` or
/// `{"template_id":"soap","transcript":{...}}`.
///
/// Output JSON: `{"ok":true,"note":{...}}` or `{"ok":false,"error":"..."}`.
///
/// # Safety
/// `request_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_note_from_transcript(request_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: NoteRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;

        let encounter = match request.encounter {
            Some(encounter) => encounter,
            None => {
                let template_id = request.template_id.clone().ok_or_else(|| {
                    "request needs either `encounter` or `template_id`".to_owned()
                })?;
                let discipline = Discipline::from_key(&template_id);
                Encounter::new("local-anonymous", discipline).with_template(template_id)
            }
        };

        let pipeline = ScribePipeline::new().map_err(|err| err.to_string())?;
        let template = pipeline
            .templates()
            .get(encounter.template_id.as_str())
            .map_err(|err| err.to_string())?;

        let generator = scribe_note::RuleBasedGenerator;
        let note: ClinicalNote = scribe_note::NoteGenerator::generate(
            &generator,
            &scribe_note::GenerationRequest {
                encounter: &encounter,
                transcript: &request.transcript,
                template,
            },
        )
        .map_err(|err| err.to_string())?;

        Ok(json!({ "ok": true, "note": note }))
    })()
    .unwrap_or_else(|error| error_envelope(error.to_string()));

    into_c_string(&payload.to_string())
}

/// Input: a note JSON object. Output: `{"ok":true,"markdown":"..."}`.
///
/// # Safety
/// `note_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_note_to_markdown(note_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(note_json) }?;
        let note: ClinicalNote =
            serde_json::from_str(&raw).map_err(|err| format!("invalid note json: {err}"))?;
        Ok(json!({ "ok": true, "markdown": note.to_markdown() }))
    })()
    .unwrap_or_else(|error| error_envelope(error.to_string()));

    into_c_string(&payload.to_string())
}

#[derive(Debug, Deserialize)]
struct TextRequest {
    #[serde(default)]
    template_id: Option<String>,
    #[serde(default)]
    patient_ref: Option<String>,
    #[serde(default)]
    discipline: Option<String>,
    text: String,
}

/// The plain-text path: a pasted or human-typed transcript in, a note out. No
/// audio, no model. This is the entry point the app uses for its bundled
/// demonstration and for a clinician who already has a transcript.
///
/// Input JSON:
/// `{"template_id":"soap","patient_ref":"opaque","discipline":"general_practice","text":"..."}`
/// Output: `{"ok":true,"note":{...},"transcript":{...}}`.
///
/// # Safety
/// `request_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_note_from_text(request_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: TextRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;

        if request.text.trim().is_empty() {
            return Err("`text` is empty".to_owned());
        }

        let discipline = request
            .discipline
            .as_deref()
            .map(Discipline::from_key)
            .unwrap_or(Discipline::GeneralPractice);
        let patient_ref = request
            .patient_ref
            .unwrap_or_else(|| "local-anonymous".to_owned());

        let mut encounter = Encounter::new(patient_ref, discipline);
        if let Some(template_id) = request.template_id {
            encounter.template_id = scribe_core::TemplateId::new(template_id);
        }

        let pipeline = ScribePipeline::new().map_err(|err| err.to_string())?;
        let output = pipeline
            .process_text(&encounter, &request.text)
            .map_err(|err| err.to_string())?;

        Ok(json!({
            "ok": true,
            "note": output.note,
            "transcript": output.transcript,
        }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Free a string returned by this library. Passing null is a no-op.
///
/// # Safety
/// `pointer` must be a pointer previously returned by one of the
/// `scribe_*` functions in this module, or null. It must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_string_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(pointer));
    }
}

fn error_envelope(error: String) -> Value {
    json!({ "ok": false, "error": error })
}

/// # Safety
/// `pointer` must be null or a valid NUL-terminated UTF-8 string.
unsafe fn cstr_to_string(pointer: *const c_char) -> Result<String, String> {
    if pointer.is_null() {
        return Err("null pointer".to_owned());
    }
    unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map(|s| s.to_owned())
        .map_err(|err| format!("input was not valid UTF-8: {err}"))
}

fn into_c_string(value: &str) -> *mut c_char {
    match CString::new(value) {
        Ok(cstring) => cstring.into_raw(),
        // A NUL inside the payload should be impossible because serde escapes
        // it, but never panic across an FFI boundary.
        Err(_) => CString::new(r#"{"ok":false,"error":"payload contained a NUL byte"}"#)
            .expect("static fallback is valid")
            .into_raw(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scribe_core::{EncounterId, Speaker, SpeakerId, SpeakerRole};

    fn sample_transcript_json() -> String {
        let mut transcript = Transcript::new(EncounterId::new(), "test");
        transcript.push_speaker(Speaker::new(SpeakerId::CLINICIAN, SpeakerRole::Clinician));
        transcript.push_segment(scribe_core::Segment::new(
            SpeakerId::CLINICIAN,
            0,
            1000,
            "On examination the throat shows erythema.",
        ));
        serde_json::to_string(&transcript).unwrap()
    }

    #[test]
    fn generates_a_note_from_a_minimal_request() {
        let request = format!(
            r#"{{"template_id":"soap","transcript":{}}}"#,
            sample_transcript_json()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { scribe_note_from_transcript(input.as_ptr()) };

        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], true);
        assert_eq!(json["note"]["template_id"], "soap");
        assert_eq!(json["note"]["engine"], "rule-based-v1");
    }

    #[test]
    fn bad_input_returns_an_error_envelope_not_a_panic() {
        let input = CString::new("{not json").unwrap();
        let output = unsafe { scribe_note_from_transcript(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], false);
        assert!(
            json["error"]
                .as_str()
                .unwrap()
                .contains("invalid request json")
        );
    }

    #[test]
    fn templates_are_listed() {
        let output = scribe_list_templates();
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], true);
        assert!(json["templates"].as_array().unwrap().len() >= 5);
    }

    #[test]
    fn generates_a_note_from_plain_text() {
        let request = serde_json::json!({
            "template_id": "soap",
            "patient_ref": "demo-001",
            "discipline": "general_practice",
            "text": "CLINICIAN: On examination the throat shows erythema.\nCLINICIAN: Plan: rest and fluids, paracetamol 1g four times a day.",
        })
        .to_string();

        let input = CString::new(request).unwrap();
        let output = unsafe { scribe_note_from_text(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], true, "{json}");
        assert_eq!(json["note"]["template_id"], "soap");
        assert_eq!(json["transcript"]["engine"], "human-transcript");
        assert!(
            json["note"]["sections"]
                .as_array()
                .unwrap()
                .iter()
                .any(|s| s["key"] == "plan" && s["body"].as_str().unwrap().contains("paracetamol")),
            "{json}"
        );
    }

    #[test]
    fn empty_text_is_an_error_envelope() {
        let input = CString::new(r#"{"template_id":"soap","text":"   "}"#).unwrap();
        let output = unsafe { scribe_note_from_text(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], false);
        assert!(json["error"].as_str().unwrap().contains("empty"));
    }

    #[test]
    fn null_free_is_safe() {
        unsafe { scribe_string_free(std::ptr::null_mut()) };
    }
}
