//
// KlinoteCore.swift
//
// The Swift face of the Rust engine. Everything clinical — transcription,
// diarisation, templates, routing, completeness, storage — lives on the other
// side of this file. The shell renders; it does not generate.
//
// Contract (see crates/scribe-ffi/include/scribe_core_ffi.h):
//   - every returned string must be freed with scribe_string_free
//   - every payload is an envelope: {"ok": true, ...} or {"ok": false, "error": "..."}
//

import Foundation

// MARK: - Decoded models

struct EngineEnvelope<Payload: Decodable>: Decodable {
    let ok: Bool
    let error: String?
}

struct NoteEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let note: ClinicalNote?
    let transcript: Transcript?
}

struct TemplatesEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let templates: [TemplateSummary]?
}

struct NoteTextEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let text: String?
}

struct PurgeEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let deleted: Int?
}

struct StoreListEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let sessions: [StoredSession]?
}

struct TaskListEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let tasks: [ConsultTask]?
}

// MARK: - Errors

enum KlinoteCoreError: LocalizedError {
    case engine(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .engine(let message): message
        case .malformedResponse: "The engine returned a response Klinote could not read."
        }
    }
}

// MARK: - The bridge

enum KlinoteCore {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static var schemaVersion: String {
        string(from: scribe_schema_version())
    }

    static func templates() throws -> [TemplateSummary] {
        let payload: TemplatesEnvelope = try envelope(from: scribe_list_templates())
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        return payload.templates ?? []
    }

    /// The plain-text path: a transcript in, a draft note and its transcript out.
    static func note(
        fromText text: String,
        templateId: String,
        discipline: String,
        patientRef: String
    ) throws -> (note: ClinicalNote, transcript: Transcript) {
        let request: [String: String] = [
            "template_id": templateId,
            "discipline": discipline,
            "patient_ref": patientRef,
            "text": text,
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }

        let payload: NoteEnvelope = try envelope(from: scribe_note_from_text(requestJSON))
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        guard let note = payload.note, let transcript = payload.transcript else {
            throw KlinoteCoreError.malformedResponse
        }
        return (note, transcript)
    }

    /// Plain text for the record system: section titles and bodies only. No
    /// Markdown, no engine metadata, no unfiled statements, no footer. This is
    /// what `Copy note` puts on the clipboard.
    static func recordText(for note: ClinicalNote) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(note)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let payload: NoteTextEnvelope = try envelope(from: scribe_note_to_record_text(json))
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        return payload.text ?? ""
    }

    /// The audio path: a recorded .wav in, a note out, via whisper.cpp with
    /// speaker diarisation. `modelPath` points at the downloaded GGUF model;
    /// pass nil to fall back to the mock engine.
    static func note(
        fromAudio audioPath: URL,
        modelPath: URL?,
        templateId: String,
        discipline: String,
        patientRef: String
    ) throws -> (note: ClinicalNote, transcript: Transcript) {
        var request: [String: Any] = [
            "template_id": templateId,
            "discipline": discipline,
            "patient_ref": patientRef,
            "audio_path": audioPath.path,
        ]
        request["model_path"] = modelPath?.path ?? NSNull()

        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }

        let payload: NoteEnvelope = try envelope(from: scribe_note_from_audio(requestJSON))
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        guard let note = payload.note, let transcript = payload.transcript else {
            throw KlinoteCoreError.malformedResponse
        }
        return (note, transcript)
    }

    /// Rebuild a note from an already-diarised transcript (speaker swap, etc.).
    static func note(
        fromTranscript transcript: Transcript,
        templateId: String
    ) throws -> ClinicalNote {
        var transcript = transcript
        if transcript.createdAt == nil {
            transcript.createdAt = ISO8601DateFormatter().string(from: Date())
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let transcriptData = try encoder.encode(transcript)
        guard let transcriptObject = try JSONSerialization.jsonObject(with: transcriptData) as? [String: Any] else {
            throw KlinoteCoreError.malformedResponse
        }
        let request: [String: Any] = [
            "template_id": templateId,
            "transcript": transcriptObject,
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let payload: NoteEnvelope = try envelope(from: scribe_note_from_transcript(requestJSON))
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        guard let note = payload.note else { throw KlinoteCoreError.malformedResponse }
        return note
    }

    static func storePath() -> String {
        let dir = ModelDownloader.supportDirectory
        let dest = dir.appendingPathComponent("klinote.sqlite")
        let legacy = dir.appendingPathComponent("nota.sqlite")
        if !FileManager.default.fileExists(atPath: dest.path),
           FileManager.default.fileExists(atPath: legacy.path)
        {
            try? FileManager.default.moveItem(at: legacy, to: dest)
        }
        return dest.path
    }

    static func saveSession(
        patientRef: String,
        discipline: String,
        templateId: String,
        startedAt: Date,
        note: ClinicalNote,
        transcript: Transcript,
        clinician: String?
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var payload: [String: Any] = [
            "patient_ref": patientRef,
            "discipline": discipline,
            "template_id": templateId,
            "started_at": formatter.string(from: startedAt),
            "actor": clinician?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? clinician!
                : "shell",
        ]
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let noteData = try encoder.encode(note)
        let transcriptData = try encoder.encode(transcript)
        payload["note"] = try JSONSerialization.jsonObject(with: noteData)
        payload["transcript"] = try JSONSerialization.jsonObject(with: transcriptData)
        let requestData = try JSONSerialization.data(withJSONObject: payload)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let envelope: EngineEnvelope<Bool> = try envelope(
            from: scribe_store_save(storePath(), try StoreKey.hex(), requestJSON)
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not save") }
    }

    static func deleteSession(id: String) throws {
        let envelope: EngineEnvelope<Bool> = try envelope(
            from: scribe_store_delete(storePath(), try StoreKey.hex(), id)
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not delete") }
    }

    // MARK: - Tasks

    /// A task is a sentence out of the clinician's own note. Nothing infers
    /// one, so nothing can invent one.
    static func addTask(encounterId: String, text: String, sourceKey: String?) throws {
        let payload: [String: Any] = [
            "encounter_id": encounterId,
            "text": text,
            "source_key": sourceKey as Any? ?? NSNull(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let envelope: EngineEnvelope<Bool> = try envelope(
            from: scribe_task_add(storePath(), try StoreKey.hex(), json)
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not add") }
    }

    /// `encounterId` nil returns every open task, oldest first.
    static func tasks(encounterId: String?) throws -> [ConsultTask] {
        let payload: TaskListEnvelope = try envelope(
            from: scribe_task_list(storePath(), try StoreKey.hex(), encounterId)
        )
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "could not list") }
        return payload.tasks ?? []
    }

    static func setTaskDone(id: String, done: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "done": done])
        guard let json = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let envelope: EngineEnvelope<Bool> = try envelope(
            from: scribe_task_set_done(storePath(), try StoreKey.hex(), json)
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not tick") }
    }

    static func deleteTask(id: String) throws {
        let envelope: EngineEnvelope<Bool> = try envelope(
            from: scribe_task_delete(storePath(), try StoreKey.hex(), id)
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not delete") }
    }

    /// Hard-delete every encounter started before `cutoff`. Returns how many went.
    static func purge(before cutoff: Date) throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let envelope: PurgeEnvelope = try envelope(
            from: scribe_store_purge(storePath(), try StoreKey.hex(), formatter.string(from: cutoff))
        )
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not purge") }
        return envelope.deleted ?? 0
    }

    /// Save one template as a practice override.
    static func saveTemplate(_ template: TemplateSummary) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(template)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let envelope: EngineEnvelope<Bool> = try envelope(from: scribe_template_save(json))
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not save") }
    }

    /// Remove a practice override, restoring the built-in.
    static func revertTemplate(id: String) throws {
        let envelope: EngineEnvelope<Bool> = try envelope(from: scribe_template_revert(id))
        guard envelope.ok else { throw KlinoteCoreError.engine(envelope.error ?? "could not revert") }
    }

    /// Where this practice's own templates live, for showing in Settings.
    static var templatesDirectory: URL {
        ModelDownloader.supportDirectory.appendingPathComponent("Templates", isDirectory: true)
    }

    static func loadSessions() throws -> [StoredSession] {
        let payload: StoreListEnvelope = try envelope(
            from: scribe_store_list(storePath(), try StoreKey.hex())
        )
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "could not load") }
        return payload.sessions ?? []
    }

    // MARK: - Plumbing

    private static func envelope<T: Decodable>(from pointer: UnsafeMutablePointer<CChar>?) throws -> T {
        let json = string(from: pointer)
        guard let data = json.data(using: .utf8) else { throw KlinoteCoreError.malformedResponse }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw KlinoteCoreError.engine("Could not read the engine response: \(error)")
        }
    }

    /// Copies the engine's string and frees the original. Never leaks, never
    /// frees twice.
    private static func string(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return #"{"ok":false,"error":"the engine returned nothing"}"# }
        defer { scribe_string_free(pointer) }
        return String(cString: pointer)
    }
}
