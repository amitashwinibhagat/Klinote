//
// Encounter.swift
//
// A consult as the shell holds it: the model, and the two decisions the list
// makes about it. Pure, so it can be tested without the app.
//

import Foundation

enum NoteState: String {
    case draft, edited, approved, failed

    var word: String { rawValue.capitalized }
}

struct Encounter: Identifiable {
    let id: String
    var patientRef: String
    var discipline: String
    var templateId: String
    var startedAt: Date
    var state: NoteState
    var note: ClinicalNote?
    var transcript: Transcript?
    /// Which clinician was at the desk when this was saved.
    var clinicianRef: String? = nil
    /// True when the note was produced from the bundled sample rather than a
    /// real recording. The interface must say so, in the document itself.
    var isSyntheticDemo: Bool
    /// True when this is a letter or patient copy derived from another
    /// encounter's transcript rather than a recording of its own.
    var isDerived: Bool = false

    var durationMs: UInt64? {
        guard let transcript else { return nil }
        return transcript.segments.map(\.endMs).max()
    }

    /// What the menu bar shows: time and template, never an opaque code.
    var menuTitle: String {
        let time = Encounter.menuTimeFormatter.string(from: startedAt)
        if isSyntheticDemo {
            return "Sample · \(templateId) · \(state.word)"
        }
        return "\(time) · \(templateId) · \(state.word)"
    }
}


/// What a session code may look like.
///
/// `patient_ref` is a pseudonym, not a place to type a name. The shell owns the
/// mapping; the core only ever sees an opaque code. The rename dialog used to
/// accept any text, so a name typed there became an identifier in the Rust
/// store, which is exactly what the contract forbids.
enum PatientReference {
    static func isOpaqueCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        // A bare word is far more likely to be a name than a code. Require at
        // least one digit or separator, which every generated reference has.
        guard trimmed.contains(where: { $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
            return false
        }
        return trimmed.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}

extension Encounter {
    /// Built once. The menu is rebuilt on every recording tick.
    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

