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

    /// Put the clinician's own lines back after a model has written the note
    /// again.
    ///
    /// A redraft replaces every section with what the model produced. A line the
    /// clinician typed is not in the transcript the model read — the model
    /// cannot reproduce it and never sees it — so replacing the note silently
    /// deleted it, and left the record marked "Edited" as though they had been
    /// the one to write the model's text. That is the same silent replacement
    /// the rest of this file exists to prevent.
    ///
    /// Appended, not interleaved. The model's draft is rewritten prose, so there
    /// is no honest way to know where a sentence it never saw belongs; last in
    /// the section is predictable and the clinician can move it.
    ///
    /// Safe to run twice: a line whose text is already in the section is not
    /// added again, so a merge of a merge cannot multiply anything.
    static func carryingAuthoredLines(
        from existing: ClinicalNote,
        into redrafted: ClinicalNote
    ) -> ClinicalNote {
        var note = redrafted
        for source in existing.sections {
            let authored = source.sentences.filter(\.isAuthored)
            guard !authored.isEmpty else { continue }
            // Same key or nothing. A different template is a different
            // question, and moving a line into a section that was not written
            // for it would be worse than leaving it out.
            guard let index = note.sections.firstIndex(where: { $0.key == source.key }) else {
                continue
            }
            let present = Set(note.sections[index].sentences.map(\.text))
            let missing = authored.filter { !present.contains($0.text) }
            guard !missing.isEmpty else { continue }

            note.sections[index].sentences.append(contentsOf: missing)
            // The body is what the clipboard is built from, so a line restored
            // into `sentences` and not into `body` would be on screen and
            // missing from the note that gets pasted.
            note.sections[index].body = note.sections[index].sentences
                .map(\.text)
                .joined(separator: " ")
            note.sections[index].complete = true
            note.missingRequired.removeAll { $0 == source.key }
        }
        return note
    }
}
