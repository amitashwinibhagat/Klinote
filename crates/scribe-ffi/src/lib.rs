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

use scribe_core::{ClinicalNote, Discipline, Encounter, SCHEMA_VERSION, Template, Transcript};
use scribe_note::TemplateLibrary;
use scribe_pipeline::{AsrSegment, ScribePipeline};
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
    let result = TemplateLibrary::for_this_machine().map(|library| {
        let templates: Vec<Value> = library
            .iter()
            .map(|template| {
                json!({
                    "id": template.id.as_str(),
                    "name": template.name,
                    "discipline": template.discipline,
                    "version": template.version,
                    "description": template.description,
                    "voice": template.voice,
                    "family": template.family,
                    "render": template.render,
                    "audience": template.audience,
                    "sections": template.sections.iter().map(|section| json!({
                        "key": section.key,
                        "title": section.title,
                        "guidance": section.guidance,
                        "required": section.required,
                        "cues": section.cues,
                        "actions": section.actions,
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

        // Through the pipeline, not around it. This used to build a
        // `RuleBasedGenerator` by hand and look up the template itself, which
        // meant `verify_support` never ran and the note carried no grounding at
        // all — see `ScribePipeline::generate`.
        let note = pipeline
            .generate(&encounter, &request.transcript)
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

/// Input: a note JSON object. Output: `{"ok":true,"text":"..."}` — plain
/// text for the record system (no Markdown, no metadata).
///
/// # Safety
/// `note_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_note_to_record_text(note_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(note_json) }?;
        let note: ClinicalNote =
            serde_json::from_str(&raw).map_err(|err| format!("invalid note json: {err}"))?;
        Ok(json!({ "ok": true, "text": note.to_record_text() }))
    })()
    .unwrap_or_else(|error| error_envelope(error.to_string()));

    into_c_string(&payload.to_string())
}

/// Save one template as a practice override. Input: a Template JSON object
/// (the same shape `scribe_list_templates` returns).
/// Output: `{"ok":true,"path":"..."}`.
///
/// # Safety
/// `template_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_template_save(template_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(template_json) }?;
        let template: Template =
            serde_json::from_str(&raw).map_err(|err| format!("invalid template json: {err}"))?;
        let path = TemplateLibrary::save_override(&template).map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true, "path": path.to_string_lossy() }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Remove a practice override, restoring the built-in.
/// Output: `{"ok":true,"removed":true|false}`.
///
/// # Safety
/// `template_id` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_template_revert(template_id: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let id = unsafe { cstr_to_string(template_id) }?;
        let removed = TemplateLibrary::delete_override(&id).map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true, "removed": removed }))
    })()
    .unwrap_or_else(error_envelope);

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

#[derive(Debug, Deserialize)]
struct VerifyRequest {
    note: ClinicalNote,
    transcript: Transcript,
}

/// Ground a note that was drafted outside the core.
///
/// Every Rust path runs `verify_support` inside `ScribePipeline::generate`. A note
/// drafted in the shell — `NoteDrafter`, on the system model — is built there and
/// never passes through the pipeline, so its `support` was an assumption rather
/// than a finding. This is that check, offered across the boundary.
///
/// Deterministic and local: it reads the transcript it is given, marks sentences,
/// and never rewrites, blocks or invents.
///
/// Input:  {"note":{...},"transcript":{...}}
/// Output: {"ok":true,"note":{...}}   (the note with `support` set)
///         | {"ok":false,"error":"..."}
///
/// # Safety
/// `request_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_verify_note(request_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: VerifyRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;

        let mut note = request.note;
        note.verify_support(&request.transcript);

        Ok(json!({ "ok": true, "note": note }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

#[derive(Debug, Deserialize)]
struct SegmentsRequest {
    #[serde(default)]
    template_id: Option<String>,
    #[serde(default)]
    patient_ref: Option<String>,
    #[serde(default)]
    discipline: Option<String>,
    /// BCP-47 language the recogniser used, recorded on the transcript.
    #[serde(default)]
    language: Option<String>,
    /// Which recogniser produced these words — `"apple-speechanalyzer"` from the
    /// macOS shell. Recorded on the transcript, because a note that says how it
    /// was heard is a note a clinician can judge.
    #[serde(default)]
    engine: Option<String>,
    /// Path to the recording the segments came from.
    ///
    /// Needed for the two speakers, and not merely nice to have: the system
    /// recogniser reports *contiguous* ranges, so the silence between turns is
    /// not in the timings and the turn-taking heuristic has nothing to alternate
    /// on. The engine already owns a tested energy VAD, so the audio comes back
    /// here to be **measured**, never re-transcribed. Optional, so a caller with
    /// no audio still works — at the cost of one speaker, which the caller
    /// should know it is choosing.
    #[serde(default)]
    audio_path: Option<String>,
    segments: Vec<SegmentRequest>,
}

#[derive(Debug, Deserialize)]
struct SegmentRequest {
    start_ms: u64,
    end_ms: u64,
    text: String,
    #[serde(default)]
    confidence: Option<f32>,
}

/// Recognised words in, a note out.
///
/// The shell does speech recognition, because `SpeechAnalyzer` is a Swift API.
/// This is where the words come back across the boundary: the pipeline still
/// owns diarisation, role mapping, grounding and completeness, so the shell must
/// not assemble those itself.
///
/// Note what is *not* here any more: an engine argument. The Rust core has no
/// speech engine reachable from this boundary, and that is deliberate — the old
/// audio entry point fell back to `MockAsrEngine` when no model was supplied,
/// which is synthetic clinical text arriving in a clinician's record. A missing
/// recogniser must now be a failure the caller sees.
///
/// Input:  {"template_id":"soap","patient_ref":"opaque",
///          "discipline":"general_practice","language":"en",
///          "engine":"apple-speechanalyzer",
///          "segments":[{"start_ms":0,"end_ms":4000,"text":"...","confidence":0.9}]}
/// Output: {"ok":true,"note":{...},"transcript":{...},"speech_spans":[...]}
///         | {"ok":false,"error":"..."}
///
/// # Safety
/// `request_json` must be null or a valid NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_note_from_segments(request_json: *const c_char) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: SegmentsRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;

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

        let segments: Vec<AsrSegment> = request
            .segments
            .into_iter()
            .map(|segment| AsrSegment {
                start_ms: segment.start_ms,
                end_ms: segment.end_ms,
                text: segment.text,
                confidence: segment.confidence,
                // No speaker: the recogniser does not know who is talking.
                // RoleMap and the diarizer decide, in the pipeline.
                speaker: None,
            })
            .collect();

        let pipeline = ScribePipeline::new().map_err(|err| err.to_string())?;
        let language = request.language.unwrap_or_else(|| "en".to_owned());
        let engine = request.engine.unwrap_or_else(|| "shell".to_owned());

        // The recording goes to the pipeline, which runs the VAD and hands the
        // waveform to the diarizer. Recognition already happened in the shell —
        // this is measurement, never a second transcription.
        let audio = match request.audio_path.as_deref() {
            Some(path) => Some(scribe_audio::load_wav(path).map_err(|err| err.to_string())?),
            None => None,
        };

        let output = pipeline
            .process_segments(&encounter, &segments, audio.as_ref(), &language, &engine)
            .map_err(|err| err.to_string())?;

        let spans: Vec<Value> = output
            .speech_spans
            .iter()
            .map(|span| json!({ "start_ms": span.start_ms, "end_ms": span.end_ms }))
            .collect();

        Ok(json!({
            "ok": true,
            "note": output.note,
            "transcript": output.transcript,
            "speech_spans": spans,
        }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

#[derive(Debug, Deserialize)]
struct StoreSaveRequest {
    patient_ref: String,
    #[serde(default)]
    discipline: Option<String>,
    #[serde(default)]
    template_id: Option<String>,
    #[serde(default)]
    started_at: Option<String>,
    note: ClinicalNote,
    transcript: Transcript,
    #[serde(default)]
    actor: Option<String>,
}

/// Persist a note and transcript. Input: db path + JSON payload.
/// Output: `{"ok":true}` | `{"ok":false,"error":"..."}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_store_save(
    db_path: *const c_char,
    key: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: StoreSaveRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;

        let discipline = request
            .discipline
            .as_deref()
            .map(Discipline::from_key)
            .unwrap_or(Discipline::GeneralPractice);
        let mut encounter = Encounter::new(&request.patient_ref, discipline);
        encounter.id = request.note.encounter_id;
        // Who was at the desk. A practice Mac may be shared, and "reviewed by
        // you" is not a signature.
        if let Some(actor) = request.actor.as_deref().filter(|a| *a != "shell") {
            encounter.clinician_ref = Some(actor.to_owned());
        }
        if let Some(template_id) = request.template_id {
            encounter.template_id = scribe_core::TemplateId::new(template_id);
        }
        if let Some(started) = request.started_at.as_deref() {
            if let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(started) {
                encounter.started_at = parsed.with_timezone(&chrono::Utc);
            }
        }

        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        store
            .save_encounter(&encounter)
            .map_err(|err| err.to_string())?;
        store
            .save_transcript(&request.transcript)
            .map_err(|err| err.to_string())?;
        store
            .save_note(&request.note)
            .map_err(|err| err.to_string())?;
        store
            .audit(
                request.actor.as_deref().unwrap_or("shell"),
                "note.saved",
                Some(&request.note.id.to_string()),
                None,
            )
            .map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// List persisted sessions, newest first.
/// Output: `{"ok":true,"sessions":[...]}`.
///
/// # Safety
/// `db_path` must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_store_list(
    db_path: *const c_char,
    key: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        let sessions = store.list_sessions().map_err(|err| err.to_string())?;
        let items: Vec<Value> = sessions
            .into_iter()
            .map(|session| {
                json!({
                    "patient_ref": session.encounter.patient_ref,
                    "clinician_ref": session.encounter.clinician_ref,
                    "id": session.encounter.id,
                    "discipline": session.encounter.discipline.as_str(),
                    "template_id": session.encounter.template_id.as_str(),
                    "started_at": session.encounter.started_at.to_rfc3339(),
                    "note": session.note,
                    "transcript": session.transcript,
                })
            })
            .collect();
        Ok(json!({ "ok": true, "sessions": items }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Hard-delete one encounter. Output: `{"ok":true}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_store_delete(
    db_path: *const c_char,
    key: *const c_char,
    encounter_id: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let id = unsafe { cstr_to_string(encounter_id) }?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        store.delete_encounter(&id).map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Hard-delete every encounter started before `cutoff_rfc3339`.
/// Output: `{"ok":true,"deleted":N}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_store_purge(
    db_path: *const c_char,
    key: *const c_char,
    cutoff_rfc3339: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let raw = unsafe { cstr_to_string(cutoff_rfc3339) }?;
        let cutoff = chrono::DateTime::parse_from_rfc3339(&raw)
            .map_err(|err| format!("invalid cutoff: {err}"))?
            .with_timezone(&chrono::Utc);
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        let deleted = store
            .delete_older_than(cutoff)
            .map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true, "deleted": deleted }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Add a task the consult asked for. Input: `{"encounter_id":"..","text":"..",
/// "source_key":"plan"}`. Re-adding the same text is a no-op.
/// Output: `{"ok":true,"added":true|false}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_task_add(
    db_path: *const c_char,
    key: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: TaskRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        let added = store
            .add_task(
                &request.encounter_id,
                &request.text,
                request.source_key.as_deref(),
            )
            .map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true, "added": added }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Tasks for one consult (`?encounter_id=`) or every open task (omitted).
/// Output: `{"ok":true,"tasks":[{id,encounter_id,text,source_key,created_at,done}]}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_task_list(
    db_path: *const c_char,
    key: *const c_char,
    encounter_id: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let encounter = unsafe { optional_cstr(encounter_id) }?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        // None: every open task. An empty string: every task, open or done,
        // so the shell can rebuild its whole picture from one read. An id:
        // that consult's tasks.
        let tasks = match encounter.as_deref() {
            Some("") => store.all_tasks(),
            Some(id) => store.tasks_for(id),
            None => store.open_tasks(),
        }
        .map_err(|err| err.to_string())?;
        let items: Vec<Value> = tasks
            .into_iter()
            .map(|task| {
                json!({
                    "id": task.id,
                    "encounter_id": task.encounter_id,
                    "text": task.text,
                    "source_key": task.source_key,
                    "created_at": task.created_at,
                    "done": task.done,
                })
            })
            .collect();
        Ok(json!({ "ok": true, "tasks": items }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Tick or untick a task. Input: `{"id":"..","done":true}`.
/// Output: `{"ok":true}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_task_set_done(
    db_path: *const c_char,
    key: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let raw = unsafe { cstr_to_string(request_json) }?;
        let request: TaskDoneRequest =
            serde_json::from_str(&raw).map_err(|err| format!("invalid request json: {err}"))?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        store
            .set_task_done(&request.id, request.done)
            .map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

/// Delete a task. Output: `{"ok":true}`.
///
/// # Safety
/// Pointers must be null or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scribe_task_delete(
    db_path: *const c_char,
    key: *const c_char,
    task_id: *const c_char,
) -> *mut c_char {
    let payload = (|| -> Result<Value, String> {
        let path = unsafe { cstr_to_string(db_path) }?;
        let key = unsafe { optional_cstr(key) }?;
        let id = unsafe { cstr_to_string(task_id) }?;
        let store = scribe_store::Store::open_with_key(&path, key.as_deref())
            .map_err(|err| err.to_string())?;
        store.delete_task(&id).map_err(|err| err.to_string())?;
        Ok(json!({ "ok": true }))
    })()
    .unwrap_or_else(error_envelope);

    into_c_string(&payload.to_string())
}

#[derive(Debug, Deserialize)]
struct TaskRequest {
    encounter_id: String,
    text: String,
    #[serde(default)]
    source_key: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TaskDoneRequest {
    id: String,
    done: bool,
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

unsafe fn optional_cstr(pointer: *const c_char) -> Result<Option<String>, String> {
    if pointer.is_null() {
        return Ok(None);
    }
    unsafe { cstr_to_string(pointer) }.map(Some)
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
    /// Template tests share one process, one `HOME` and one
    /// `KLINOTE_TEMPLATES_DIR` — and that variable is process-global, not
    /// per-test. They cannot run beside each other: one saves an override and
    /// sets the variable, another lists templates and reads it. On CI that
    /// raced and `templates_are_listed` saw a single template instead of five,
    /// on a commit whose other run had just passed.
    ///
    /// The comment in the save test used to say it "owns the variable". Nothing
    /// in Rust makes that true; the lock does.
    static TEMPLATES: std::sync::Mutex<()> = std::sync::Mutex::new(());

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

    /// The contract the Settings editor depends on: it hands back the exact
    /// JSON that `scribe_list_templates` returned, with a field changed, and
    /// the engine must accept it, persist it, and use it.
    #[test]
    fn template_save_accepts_listed_json_and_takes_effect() {
        let _templates = TEMPLATES.lock().unwrap_or_else(|err| err.into_inner());

        let dir =
            std::env::temp_dir().join(format!("klinote-ffi-templates-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        // SAFETY: the value is not a pointer, and every test that reads
        // it holds TEMPLATES, so no other thread is looking.
        unsafe { std::env::set_var("KLINOTE_TEMPLATES_DIR", &dir) };

        let listed = unsafe { cstr_to_string(scribe_list_templates()) }.unwrap();
        let listed: Value = serde_json::from_str(&listed).unwrap();
        let mut soap = listed["templates"]
            .as_array()
            .unwrap()
            .iter()
            .find(|template| template["id"] == "soap")
            .expect("soap is listed")
            .clone();

        // Cues and audience must survive the round trip, or the editor cannot
        // edit them.
        assert!(soap["audience"].is_string());
        let first_cues = soap["sections"][0]["cues"].as_array().unwrap().len();
        assert!(first_cues > 0, "cues are listed");

        soap["name"] = json!("Our House SOAP");
        soap["sections"][0]["cues"] = json!(["our-cue"]);
        let input = CString::new(soap.to_string()).unwrap();
        let saved = unsafe { scribe_template_save(input.as_ptr()) };
        let saved: Value =
            serde_json::from_str(&unsafe { cstr_to_string(saved) }.unwrap()).unwrap();
        assert_eq!(saved["ok"], true, "save failed: {saved}");

        // The engine now reads the practice's version.
        let relisted = unsafe { cstr_to_string(scribe_list_templates()) }.unwrap();
        let relisted: Value = serde_json::from_str(&relisted).unwrap();
        let soap = relisted["templates"]
            .as_array()
            .unwrap()
            .iter()
            .find(|template| template["id"] == "soap")
            .unwrap();
        assert_eq!(soap["name"], "Our House SOAP");
        assert_eq!(soap["sections"][0]["cues"], json!(["our-cue"]));

        // And reverting brings the built-in back.
        let id = CString::new("soap").unwrap();
        let reverted = unsafe { scribe_template_revert(id.as_ptr()) };
        let reverted: Value =
            serde_json::from_str(&unsafe { cstr_to_string(reverted) }.unwrap()).unwrap();
        assert_eq!(reverted["removed"], true);
        let after = unsafe { cstr_to_string(scribe_list_templates()) }.unwrap();
        let after: Value = serde_json::from_str(&after).unwrap();
        let soap = after["templates"]
            .as_array()
            .unwrap()
            .iter()
            .find(|template| template["id"] == "soap")
            .unwrap();
        assert_eq!(soap["name"], "SOAP Note");

        let _ = std::fs::remove_dir_all(&dir);
        // SAFETY: as above.
        // SAFETY: as above.
        unsafe { std::env::remove_var("KLINOTE_TEMPLATES_DIR") };
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
        let _templates = TEMPLATES.lock().unwrap_or_else(|err| err.into_inner());

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
    fn segments_path_produces_a_note_and_records_its_engine() {
        let request = serde_json::json!({
            "template_id": "soap",
            "patient_ref": "demo-segments",
            "discipline": "general_practice",
            "language": "en",
            "engine": "apple-speechanalyzer",
            "segments": [
                {"start_ms": 0, "end_ms": 4000, "text": "Good morning, what brings you in today?"},
                {"start_ms": 5000, "end_ms": 9000, "text": "I have had a sore throat for four days."},
                {"start_ms": 10000, "end_ms": 14000, "text": "On examination the throat shows erythema."},
                {"start_ms": 15000, "end_ms": 19000, "text": "Plan: rest and fluids, follow up in one week."}
            ]
        })
        .to_string();
        let input = CString::new(request).unwrap();
        let output = unsafe { scribe_note_from_segments(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], true, "{json}");
        assert_eq!(json["transcript"]["engine"], "apple-speechanalyzer");
        assert_eq!(json["transcript"]["segments"].as_array().unwrap().len(), 4);
        // These fixture segments carry a second of silence between each turn, so
        // the heuristic finds both voices from the timings alone. Real
        // `SpeechTranscriber` output does not — its ranges are contiguous — which
        // is what `segments_with_the_audio_find_both_voices` covers.
        assert_eq!(json["transcript"]["speakers"].as_array().unwrap().len(), 2);
        assert_eq!(json["speech_spans"].as_array().unwrap().len(), 4);
    }

    /// The reason `audio_path` exists.
    ///
    /// `SpeechTranscriber` reports contiguous ranges — one result ends exactly
    /// where the next begins — so the silence that separates two voices is not
    /// in the timings at all. Measured from the recording, it is.
    #[test]
    fn segments_with_the_audio_find_both_voices() {
        let dir = std::env::temp_dir().join("scribe-ffi-segments-test");
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("two-voices.wav");

        let rate = 16_000u32;
        let tone = |ms: u64, freq: f32| -> Vec<i16> {
            let count = (rate as u64 * ms / 1000) as usize;
            (0..count)
                .map(|i| {
                    let t = i as f32 / rate as f32;
                    ((2.0 * std::f32::consts::PI * freq * t).sin() * 0.5 * i16::MAX as f32) as i16
                })
                .collect()
        };
        let silence = |ms: u64| -> Vec<i16> { vec![0i16; (rate as u64 * ms / 1000) as usize] };

        // One turn, a 1.5 s silent gap, a second turn.
        let mut samples = silence(500);
        samples.extend(tone(1500, 220.0));
        samples.extend(silence(1500));
        samples.extend(tone(1500, 300.0));
        samples.extend(silence(500));

        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&wav, spec).unwrap();
        for sample in samples {
            writer.write_sample(sample).unwrap();
        }
        writer.finalize().unwrap();

        let request = serde_json::json!({
            "template_id": "soap",
            "audio_path": wav.to_string_lossy(),
            "segments": [
                {"start_ms": 500, "end_ms": 2000, "text": "On examination the throat shows erythema."},
                {"start_ms": 3500, "end_ms": 5000, "text": "I have had a sore throat for four days."}
            ]
        })
        .to_string();
        let input = CString::new(request).unwrap();
        let output = unsafe { scribe_note_from_segments(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], true, "{json}");
        assert_eq!(
            json["transcript"]["speakers"].as_array().unwrap().len(),
            2,
            "the recording carries the silence between the two turns: {json}"
        );
    }

    /// Segment timings are the diariser's only input, so a segment missing one
    /// is nonsense and must be reported rather than defaulted.
    #[test]
    fn segments_path_rejects_a_malformed_request() {
        let request = serde_json::json!({
            "template_id": "soap",
            "segments": [{"start_ms": 0, "text": "missing end_ms"}]
        })
        .to_string();
        let input = CString::new(request).unwrap();
        let output = unsafe { scribe_note_from_segments(input.as_ptr()) };
        let json: Value =
            serde_json::from_str(&unsafe { cstr_to_string(output) }.unwrap()).unwrap();
        unsafe { scribe_string_free(output) };

        assert_eq!(json["ok"], false);
        assert!(
            json["error"]
                .as_str()
                .unwrap()
                .contains("invalid request json"),
            "{json}"
        );
    }

    #[test]
    fn null_free_is_safe() {
        unsafe { scribe_string_free(std::ptr::null_mut()) };
    }
}
