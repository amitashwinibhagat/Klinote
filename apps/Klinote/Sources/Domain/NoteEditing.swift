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

/// Provenance words for a line a person produced.
enum LineAuthorship {
    /// Typed outright by the clinician, including "Add a line".
    static let clinician = "clinician"
    /// A line the engine drafted that the clinician has rewritten.
    static let clinicianEdited = "clinician-edited"
}

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
                authored: LineAuthorship.clinician,
                lineId: lineId
            )
        )
        rebuildSection(&note.sections[index])
        note.missingRequired.removeAll { $0 == key }
        return note
    }

    /// Recompute everything derived from a section's sentences: the body the
    /// clipboard is built from, the evidence set, and whether the section
    /// counts as documented.
    ///
    /// Excluded sentences are skipped: a removed line is not in the note the
    /// clinician signs, so it must not be in the body that is copied either.
    /// A section left with no present sentences is empty again — and if it is
    /// required, the caller recomputes `missingRequired` below.
    static func rebuildSection(_ section: inout NoteSection) {
        let present = section.sentences.filter(\.isPresent)
        section.body = present
            .map(\.text)
            .joined(separator: " ")
        section.evidence = Array(Set(present.flatMap(\.evidence))).sorted()
        section.complete = !section.body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Recompute `missingRequired` from the sections themselves. One rule in
    /// one place: a required section whose present content is empty is
    /// missing, whatever happened to its last line — written once, moved out,
    /// or excluded.
    ///
    /// The required set comes from the template, passed in by the caller:
    /// the engine's own `missing_required` list is only a draft-time snapshot
    /// (it names required sections that were empty *at drafting*), so it
    /// cannot see a section the clinician emptied by moving or excluding its
    /// last line. With the template's flags this is a pure recomputation:
    /// required ∧ empty = missing, nothing else is ever listed.
    static func recomputeMissingRequired(
        for note: inout ClinicalNote,
        requiredKeys: Set<String>
    ) {
        var missing: [String] = []
        for section in note.sections {
            let isEmpty = section.body.trimmingCharacters(in: .whitespaces).isEmpty
            if requiredKeys.contains(section.key)
                && isEmpty
                && !missing.contains(section.key)
            {
                missing.append(section.key)
            }
        }
        note.missingRequired = missing
    }

    /// The same recomputation where the caller has no template to hand —
    /// tests, and callers operating on notes already stripped of context.
    /// Treats the engine's list as the required set: it clears resolved
    /// sections but cannot discover new ones. AppModel always has the
    /// template and uses the full form above.
    static func recomputeMissingRequired(for note: inout ClinicalNote) {
        recomputeMissingRequired(for: &note, requiredKeys: Set(note.missingRequired))
    }

    // MARK: - Moving a sentence

    /// Move a sentence (by stable id) into another section. The sentence
    /// keeps its text, evidence and provenance — only its home changes.
    /// Returns nil when either section or the line is missing.
    static func moving(
        sentenceID: String,
        toSection key: String,
        in note: ClinicalNote,
        requiredKeys: Set<String>
    ) -> ClinicalNote? {
        guard key != "",
              let destination = note.sections.firstIndex(where: { $0.key == key })
        else { return nil }

        var note = note
        guard let source = note.sections.firstIndex(where: { section in
            section.sentences.contains { $0.id == sentenceID }
        }), source != destination else { return nil }

        guard let index = note.sections[source].sentences.firstIndex(where: { $0.id == sentenceID })
        else { return nil }
        let sentence = note.sections[source].sentences.remove(at: index)
        note.sections[destination].sentences.append(sentence)

        rebuildSection(&note.sections[source])
        rebuildSection(&note.sections[destination])
        recomputeMissingRequired(for: &note, requiredKeys: requiredKeys)
        return note
    }

    // MARK: - Exclusion — a decision, reversible, never a drop

    /// Exclude a sentence from the note. The sentence and its evidence stay
    /// in the JSON so the decision can be undone and the margin can still
    /// show what it was; rendering, completeness and the clipboard skip it.
    static func excluding(sentenceID: String, in note: ClinicalNote, requiredKeys: Set<String>) -> ClinicalNote? {
        var note = note
        guard let sectionIndex = note.sections.firstIndex(where: { section in
            section.sentences.contains { $0.id == sentenceID }
        }) else { return nil }
        guard let sentenceIndex = note.sections[sectionIndex].sentences.firstIndex(where: { $0.id == sentenceID })
        else { return nil }
        guard note.sections[sectionIndex].sentences[sentenceIndex].isPresent else { return nil }

        note.sections[sectionIndex].sentences[sentenceIndex].excluded = true
        rebuildSection(&note.sections[sectionIndex])
        recomputeMissingRequired(for: &note, requiredKeys: requiredKeys)
        return note
    }

    /// Restore an excluded sentence.
    static func restoring(sentenceID: String, in note: ClinicalNote, requiredKeys: Set<String>) -> ClinicalNote? {
        var note = note
        guard let sectionIndex = note.sections.firstIndex(where: { section in
            section.sentences.contains { $0.id == sentenceID }
        }) else { return nil }
        guard let sentenceIndex = note.sections[sectionIndex].sentences.firstIndex(where: { $0.id == sentenceID })
        else { return nil }
        guard note.sections[sectionIndex].sentences[sentenceIndex].isExcluded else { return nil }

        note.sections[sectionIndex].sentences[sentenceIndex].excluded = false
        rebuildSection(&note.sections[sectionIndex])
        recomputeMissingRequired(for: &note, requiredKeys: requiredKeys)
        return note
    }

    /// Exclude an unfiled statement: out of `unassigned`, into `excluded`,
    /// evidence intact. Returns nil when the item is not there.
    static func excludingUnfiled(_ itemID: String, from note: ClinicalNote) -> ClinicalNote? {
        guard let index = note.unassigned.firstIndex(where: { $0.id == itemID }) else { return nil }
        var note = note
        let item = note.unassigned.remove(at: index)
        var kept = note.excluded ?? []
        kept.append(
            ExcludedStatement(
                text: item.text,
                speakerRole: item.speakerRole,
                evidence: item.evidence
            )
        )
        note.excluded = kept
        return note
    }

    /// Reinstate an excluded unfiled statement — back to awaiting a decision.
    static func restoringUnfiled(_ itemID: String, from note: ClinicalNote) -> ClinicalNote? {
        guard let index = note.excluded?.firstIndex(where: { $0.id == itemID }) ?? nil else { return nil }
        var note = note
        let item = note.excluded!.remove(at: index)
        if note.excluded!.isEmpty { note.excluded = nil }
        note.unassigned.append(
            UnassignedStatement(
                text: item.text,
                speakerRole: item.speakerRole,
                evidence: item.evidence
            )
        )
        return note
    }

    // MARK: - Identity

    /// Mint a stable identity for every sentence that lacks one. Idempotent,
    /// run before any note is persisted: a line the engine wrote gains its
    /// `lineId` on first save, so correcting it later cannot change its id
    /// and lose what selection, undo and redraft protection were following.
    static func mintingLineIds(for note: ClinicalNote) -> ClinicalNote {
        var note = note
        for sectionIndex in note.sections.indices {
            for sentenceIndex in note.sections[sectionIndex].sentences.indices {
                if note.sections[sectionIndex].sentences[sentenceIndex].lineId == nil {
                    note.sections[sectionIndex].sentences[sentenceIndex].lineId = UUID().uuidString
                }
            }
        }
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
    ///
    /// Excluded *sentences* travel too. The old version carried authored lines
    /// and excluded unfiled items but not a sentence the clinician had removed,
    /// so every redraft revived it. An excluded sentence is a decision about
    /// content, exactly like an excluded unfiled statement.
    static func carryingAuthoredLines(
        from existing: ClinicalNote,
        into redrafted: ClinicalNote,
        requiredKeys: Set<String> = []
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
            rebuildSection(&note.sections[index])
            recomputeMissingRequired(
                for: &note,
                requiredKeys: requiredKeys.isEmpty ? Set(note.missingRequired) : requiredKeys
            )
        }
        // Excluded sentences: match by text in the same section, so a redraft
        // that rewrites other lines still remembers what was removed. If the
        // model dropped the sentence entirely, keep it in the JSON as excluded
        // so the decision is visible and reversible rather than forgotten.
        for source in existing.sections {
            guard let index = note.sections.firstIndex(where: { $0.key == source.key }) else {
                continue
            }
            for sentence in source.sentences where sentence.isExcluded {
                if let existingIndex = note.sections[index].sentences.firstIndex(where: {
                    $0.text == sentence.text
                }) {
                    note.sections[index].sentences[existingIndex].excluded = true
                } else {
                    note.sections[index].sentences.append(sentence)
                }
            }
            rebuildSection(&note.sections[index])
        }
        if !requiredKeys.isEmpty {
            recomputeMissingRequired(for: &note, requiredKeys: requiredKeys)
        }

        // An exclusion is a decision about content, not about one revision's
        // wording. A redraft that dropped it would quietly revive sentences
        // the clinician removed, so the decisions carry across by text.
        if let excluded = existing.excluded, !excluded.isEmpty {
            var carried = note.excluded ?? []
            let presentTexts = Set(carried.map(\.text))
            for item in excluded where !presentTexts.contains(item.text) {
                carried.append(item)
            }
            note.excluded = carried.isEmpty ? nil : carried
        }
        // If a human's line or an exclusion was carried into the model's
        // revision, the revision is no longer purely machine-written.
        if existing.sections.contains(where: { $0.sentences.contains(where: \.isAuthored) })
            || existing.sections.contains(where: { $0.sentences.contains(where: \.isExcluded) })
        {
            note.machineGenerated = false
        }
        return note
    }
}
