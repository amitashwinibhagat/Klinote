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


extension Encounter {
    /// Built once. The menu is rebuilt on every recording tick.
    static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

