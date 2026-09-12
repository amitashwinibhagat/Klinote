//
// NoteEditing.swift
//
// Adding a line the clinician wrote.
//
// The engine writes only what it heard, and that is correct: an empty required
// section means the consult did not cover it, not that the engine failed. But
// it left nowhere to go. The only way to edit a sentence was to right-click one
// that already existed, so a section the engine left empty could never be
// filled — the note could not be finished in Klinote at all, only copied out
// and completed elsewhere.
//
// A line added here is not evidence-backed, and is not passed off as if it
// were. It carries `authored`, so the margin can say a person wrote it, and its
// own id, so the checklist and the sentence selection cannot confuse two
// identical lines for each other.
//

import Foundation

enum NoteEditing {
    /// Returns nil when there is nothing to do, so the caller cannot mistake a
    /// no-op for a change worth persisting.
    static func adding(
        _ text: String,
        toSection key: String,
        in note: ClinicalNote,
        lineId: String
    ) -> ClinicalNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let index = note.sections.firstIndex(where: { $0.key == key }) else { return nil }

        var note = note
        note.sections[index].sentences.append(
            NoteSentence(
                text: trimmed,
                evidence: [],
                ambiguous: false,
                support: nil,
                wording: nil,
                authored: "clinician",
                lineId: lineId
            )
        )
        // The clipboard text is built from `body`, so a line that is not folded
        // into it would be on screen and missing from the record.
        note.sections[index].body = note.sections[index].sentences
            .map(\.text)
            .joined(separator: " ")
        note.sections[index].complete = true
        note.missingRequired.removeAll { $0 == key }
        return note
    }
}
