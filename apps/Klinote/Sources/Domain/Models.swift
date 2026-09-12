//
// Models.swift
//
// The data the product talks about, and nothing else.
//
// No FFI, no AppKit, no SwiftUI — this directory is compiled into the app and
// into the test bundle, so a unit test can exercise the logic that decides
// what a clinician sees without launching the application, opening the
// encrypted store, or touching the Keychain.
//

import Foundation

struct ConsultTask: Decodable, Identifiable, Hashable {
    let id: String
    let encounterId: String
    let text: String
    let sourceKey: String?
    let createdAt: String
    var done: Bool
}

struct StoredSession: Decodable {
    let patientRef: String
    /// Which clinician was at the desk. Nil for notes saved before this
    /// existed, and for anything saved by a tool rather than a person.
    let clinicianRef: String?
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
    var sections: [NoteSection]
    var unassigned: [UnassignedStatement]
    let generatedAt: String
    let engine: String
    let reviewState: String
    /// Keys of required sections with nothing in them. `var` because a
    /// clinician writing a line into an empty section is what clears one.
    var missingRequired: [String]
    let machineGenerated: Bool

    static func == (lhs: ClinicalNote, rhs: ClinicalNote) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct NoteSection: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    var body: String
    let evidence: [String]
    var sentences: [NoteSentence]
    /// Whether this section counts as documented. `var` for the same reason.
    var complete: Bool

    var id: String { key }
}

struct NoteSentence: Codable, Hashable, Identifiable {
    var text: String
    let evidence: [String]
    let ambiguous: Bool
    /// "supported" or "unverified". Set by the engine's grounding check.
    var support: String?
    /// "plain" or "jargon". Set only on patient-facing documents.
    var wording: String?
    /// "clinician" when a person wrote this line rather than the engine
    /// drafting it from the recording. Nil for everything the engine wrote.
    ///
    /// Optional so a note saved before a clinician could add lines still
    /// decodes — the same reason `Transcript.heldMs` is optional.
    var authored: String?
    /// Stable identity for a line a clinician added, so two identical lines in
    /// one note do not collide. Nil on engine-written sentences, which are
    /// identified by the words they came from.
    var lineId: String?

    var isUnverified: Bool { support == "unverified" }
    var isJargon: Bool { wording == "jargon" }
    /// A person wrote this. It has no words behind it, and the margin says so
    /// rather than letting it look like everything else.
    var isAuthored: Bool { authored != nil }

    /// Stable within a note: the sentence text plus its first evidence id.
    var id: String { lineId ?? "\(evidence.first ?? "none")::\(text)" }
}

struct UnassignedStatement: Codable, Identifiable, Hashable {
    let text: String
    let speakerRole: String
    let evidence: [String]

    var id: String { "\(evidence.first ?? "none")::\(text)" }
}

struct NameCheck: Codable, Hashable, Identifiable {
    let heard: String
    let suggest: String
    let evidence: [String]
    var id: String { "\(heard)|\(suggest)" }
}

struct Transcript: Codable {
    let encounterId: String
    var speakers: [TranscriptSpeaker]
    var segments: [TranscriptSegment]
    let language: String
    let engine: String
    var humanSupplied: Bool
    var createdAt: String?
    var nameChecks: [NameCheck]?
    /// Milliseconds deliberately not captured, because the clinician held the
    /// recording. Shown on the letter so a gap is explained.
    ///
    /// Optional, and it must stay optional: a consult saved before holding
    /// existed has no `held_ms`, and a synthesized decoder would refuse the
    /// whole transcript — losing the clinician's history to add a timestamp.
    var heldMs: UInt64?

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
    var text: String
    let confidence: Double?
}

struct TemplateSummary: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var discipline: String
    let version: String
    var description: String
    var voice: String?
    /// "note" or "document". Documents are the other things the consult owes:
    /// a referral letter, the patient's copy.
    let family: String?
    /// "sections" or "letter".
    let render: String?
    /// "clinical" or "patient".
    let audience: String?
    var sections: [TemplateSectionSummary]

    var isDocument: Bool { family == "document" }
    var isLetter: Bool { render == "letter" }
    var isPatientFacing: Bool { audience == "patient" }
}

struct TemplateSectionSummary: Codable, Identifiable, Hashable {
    let key: String
    var title: String
    var guidance: String
    var required: Bool
    /// The vocabulary the rule-based engine routes on. Editable per practice.
    var cues: [String]
    /// True when these sentences are work to do: the consult's checklist.
    var actions: Bool

    var id: String { key }

    /// Cues as one editable line.
    var cuesText: String {
        get { cues.joined(separator: ", ") }
        set {
            cues = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}

