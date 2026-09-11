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

struct MarkdownEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let markdown: String?
}

struct StoreListEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let sessions: [StoredSession]?
}

struct StoredSession: Decodable {
    let patientRef: String
    let discipline: String
    let templateId: String
    let startedAt: String
    let note: ClinicalNote?
    let transcript: Transcript?
}

struct ClinicalNote: Codable, Identifiable, Hashable {
    let id: String
    let encounterId: String
    let templateId: String
    let sections: [NoteSection]
    let unassigned: [UnassignedStatement]
    let generatedAt: String
    let engine: String
    let reviewState: String
    let missingRequired: [String]
    let machineGenerated: Bool

    static func == (lhs: ClinicalNote, rhs: ClinicalNote) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct NoteSection: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    let body: String
    let evidence: [String]
    let sentences: [NoteSentence]
    let complete: Bool

    var id: String { key }
}

struct NoteSentence: Codable, Hashable, Identifiable {
    let text: String
    let evidence: [String]
    let ambiguous: Bool

    /// Stable within a note: the sentence text plus its first evidence id.
    var id: String { "\(evidence.first ?? "none")::\(text)" }
}

struct UnassignedStatement: Codable, Identifiable, Hashable {
    let text: String
    let speakerRole: String
    let evidence: [String]

    var id: String { "\(evidence.first ?? "none")::\(text)" }
}

struct Transcript: Codable {
    let encounterId: String
    var speakers: [TranscriptSpeaker]
    let segments: [TranscriptSegment]
    let language: String
    let engine: String
    var humanSupplied: Bool
    var createdAt: String?

    /// Flip clinician ↔ patient on the two well-known speakers. Other roles stay.
    mutating func swapClinicianAndPatient() {
        for index in speakers.indices {
            switch speakers[index].role {
            case "clinician": speakers[index].role = "patient"
            case "patient": speakers[index].role = "clinician"
            default: break
            }
        }
    }
}

struct TranscriptSpeaker: Codable, Identifiable {
    let id: UInt32
    var role: String
    let label: String?
}

struct TranscriptSegment: Codable, Identifiable {
    let id: String
    let speaker: UInt32
    let startMs: UInt64
    let endMs: UInt64
    let text: String
    let confidence: Double?
}

struct TemplateSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let discipline: String
    let version: String
    let description: String
    let sections: [TemplateSectionSummary]
}

struct TemplateSectionSummary: Decodable, Identifiable {
    let key: String
    let title: String
    let guidance: String
    let required: Bool

    var id: String { key }
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

    /// Renders the note as Markdown using the engine's own renderer, so the
    /// copied text is identical to what the CLI produces.
    static func markdown(for note: ClinicalNote) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(note)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        let payload: MarkdownEnvelope = try envelope(from: scribe_note_to_markdown(json))
        guard payload.ok else { throw KlinoteCoreError.engine(payload.error ?? "unknown error") }
        return payload.markdown ?? ""
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
        transcript: Transcript
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var payload: [String: Any] = [
            "patient_ref": patientRef,
            "discipline": discipline,
            "template_id": templateId,
            "started_at": formatter.string(from: startedAt),
            "actor": "shell",
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
