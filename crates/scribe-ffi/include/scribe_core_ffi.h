/*
 * scribe_core_ffi.h — C ABI for the Local Clinical Scribe engine.
 *
 * Link the Rust static library built by:
 *     cargo build --release -p scribe-ffi
 * which produces target/release/libscribe_core_ffi.a
 *
 * Swift usage (add this header to a bridging header, link the .a):
 *
 *     guard let raw = scribe_note_from_transcript(requestJSON) else { return }
 *     defer { scribe_string_free(raw) }
 *     let envelope = try JSONDecoder().decode(Envelope.self,
 *                                             from: Data(String(cString: raw).utf8))
 *
 * Contract:
 *   - Every function returning `char *` returns heap-allocated, NUL-terminated
 *     UTF-8 that the caller MUST free with scribe_string_free(). Null is
 *     possible only on allocation failure.
 *   - Payload functions return an envelope:
 *         { "ok": true,  ... }
 *         { "ok": false, "error": "..." }
 *     Failures never panic across the boundary; malformed input is an error
 *     envelope, not undefined behaviour.
 *   - Input pointers must be NUL-terminated UTF-8, or NULL.
 */

#ifndef SCRIBE_CORE_FFI_H
#define SCRIBE_CORE_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/* Engine contract version, e.g. "0.1.0". Assert at launch. */
char *scribe_schema_version(void);

/*
 * JSON: {"ok":true,"templates":[{id,name,discipline,version,description,
 *                                sections:[{key,title,guidance,required}]}]}
 */
char *scribe_list_templates(void);

/*
 * Save one template as a practice override. Input is a Template JSON object of
 * the same shape `scribe_list_templates` returns.
 * Output: {"ok":true,"path":"..."} | {"ok":false,"error":"..."}
 */
char *scribe_template_save(const char *template_json);

/*
 * Remove a practice override, restoring the built-in with that id.
 * Output: {"ok":true,"removed":true|false} | {"ok":false,"error":"..."}
 */
char *scribe_template_revert(const char *template_id);

/*
 * Input:  {"encounter":{...},"transcript":{...}}  or
 *         {"template_id":"soap","transcript":{...}}
 * Output: {"ok":true,"note":{...}} | {"ok":false,"error":"..."}
 *
 * `transcript` is a serialised Transcript (see scribe-core). Use the
 * `parse_transcript_text` path in the CLI/engine for plain-text transcripts.
 */
char *scribe_note_from_transcript(const char *request_json);

/*
 * Input:  a serialised ClinicalNote (the object inside "note" above).
 * Output: {"ok":true,"markdown":"..."} | {"ok":false,"error":"..."}
 */
char *scribe_note_to_markdown(const char *note_json);

/*
 * Input:  a serialised ClinicalNote.
 * Output: {"ok":true,"text":"..."} — plain text for pasting into the record
 *         system. Section titles and bodies only: no Markdown, no engine
 *         metadata, no unfiled statements, no footer.
 */
char *scribe_note_to_record_text(const char *note_json);

/*
 * The plain-text path: a pasted or human-typed transcript in, a note out.
 * No audio, no model. Used by the app's bundled demonstration and by any
 * clinician who already has a transcript.
 *
 * Input:  {"template_id":"soap","patient_ref":"opaque",
 *          "discipline":"general_practice","text":"CLINICIAN: ...\nPATIENT: ..."}
 * Output: {"ok":true,"note":{...},"transcript":{...}} | {"ok":false,"error":"..."}
 */
char *scribe_note_from_text(const char *request_json);

/*
 * The audio path: a recorded .wav in, a note out, via whisper.cpp with
 * speaker diarisation. The model must already be on disk (the shell owns the
 * first-use download).
 *
 * Input:  {"template_id":"soap","patient_ref":"opaque",
 *          "discipline":"general_practice",
 *          "audio_path":"/path/to/recording.wav",
 *          "model_path":"/path/to/ggml-small.en-tdrz.bin"}
 *         Pass `model_path: null` to fall back to the mock engine.
 * Output: {"ok":true,"note":{...},"transcript":{...},"speech_spans":[...]}
 *         | {"ok":false,"error":"..."}
 */
char *scribe_note_from_audio(const char *request_json);

/*
 * Persist a note and transcript to a local SQLite file.
 * Input path: filesystem path to the database (created if missing).
 * Input JSON: {patient_ref, discipline, template_id, started_at, note, transcript}
 * Output: {"ok":true} | {"ok":false,"error":"..."}
 */
char *scribe_store_save(const char *db_path, const char *key, const char *request_json);

/*
 * List persisted sessions, newest first.
 * Output: {"ok":true,"sessions":[{patient_ref,discipline,template_id,started_at,note,transcript}]}
 */
char *scribe_store_list(const char *db_path, const char *key);

/* Hard-delete one encounter and its transcript/note. Audit keeps the id only. */
char *scribe_store_delete(const char *db_path, const char *key, const char *encounter_id);

/*
 * Retention: hard-delete every encounter started before `cutoff_rfc3339`.
 * Output: {"ok":true,"deleted":N} | {"ok":false,"error":"..."}
 */
char *scribe_store_purge(const char *db_path, const char *key, const char *cutoff_rfc3339);

/*
 * Tasks: what the consult asked the clinician to do. Never inferred — each row
 * is a sentence the clinician's own note contains.
 *
 * add:      {"encounter_id":"..","text":"..","source_key":"plan"}
 *           -> {"ok":true,"added":true|false}   (re-adding the same text is a no-op)
 * list:     encounter_id NULL -> every open task, else that consult's tasks
 *           -> {"ok":true,"tasks":[{id,encounter_id,text,source_key,created_at,done}]}
 * set_done: {"id":"..","done":true}
 * delete:   task id
 */
char *scribe_task_add(const char *db_path, const char *key, const char *request_json);
char *scribe_task_list(const char *db_path, const char *key, const char *encounter_id);
char *scribe_task_set_done(const char *db_path, const char *key, const char *request_json);
char *scribe_task_delete(const char *db_path, const char *key, const char *task_id);

/* Free any string returned by this library. NULL is a no-op. */
void scribe_string_free(char *pointer);

#ifdef __cplusplus
}
#endif

#endif /* SCRIBE_CORE_FFI_H */
