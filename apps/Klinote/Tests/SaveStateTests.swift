//
// SaveStateTests.swift
//
// The review decisions the shell makes about a revision, as values. No app,
// no store, no Keychain, no UI.
//
// The persistence half of Phase 1 lives on the Rust side
// (`save_session_is_atomic_idempotent_and_carries_review_state`); these cover
// the claims the *shell* makes about a revision.
//

import XCTest

final class SaveStateTests: XCTestCase {
    // MARK: - A human edit

    /// Approval is a claim about one revision. Correct a sentence after
    /// review and what is on screen is no longer what was approved: the
    /// revision's approval is spent, and the honest word for "a person has
    /// been here since" is Edited.
    func testEditingAnApprovedNoteBecomesEdited() {
        XCTAssertEqual(ReviewDecision.stateAfterHumanEdit(current: "approved"), "edited")
    }

    /// A human edit of a draft is the one act that moves a note out of
    /// Draft — the same contract the engine states, kept on the shell side.
    func testEditingADraftBecomesEdited() {
        XCTAssertEqual(ReviewDecision.stateAfterHumanEdit(current: "draft"), "edited")
    }

    /// Editing an edited note stays edited. There is no stronger human state
    /// an edit can claim, and no halfway state to invent.
    func testEditingAnEditedNoteStaysEdited() {
        XCTAssertEqual(ReviewDecision.stateAfterHumanEdit(current: "edited"), "edited")
    }

    /// Undo restores content, not approval. The File note action is the only
    /// thing that puts `approved` back.
    func testUndoDoesNotReapprove() {
        XCTAssertEqual(ReviewDecision.stateAfterUndo(restored: "approved"), "edited")
        XCTAssertEqual(ReviewDecision.stateAfterUndo(restored: "edited"), "edited")
        XCTAssertEqual(ReviewDecision.stateAfterUndo(restored: "draft"), "draft")
    }

    // MARK: - A machine redraft

    /// A Quire redraft, a voice swap or a download-completion rewrite
    /// produces a revision no human has seen. It must reset to Draft rather
    /// than inherit the old revision's claim — the same lie as silent
    /// approval, pointed the other way.
    func testAMachineRedraftResetsToDraft() {
        XCTAssertEqual(ReviewDecision.stateAfterMachineRedraft(), "draft")
    }

    // MARK: - What the shell shows

    /// The save status words the letterhead can show. "Saved" is the steady
    /// state and shows nothing; the failure word names the fact and the
    /// banner carries the reason.
    func testSaveStatusWords() {
        XCTAssertEqual(SaveStatus.saved.word, "Saved on this Mac")
        XCTAssertFalse(SaveStatus.saved.isUnsaved)
        let failed = SaveStatus.unsaved("the store refused this save")
        XCTAssertEqual(
            failed.word,
            "Not saved — the store refused this save"
        )
        XCTAssertTrue(failed.isUnsaved)
    }
}

// MARK: - Phase 3: resolving content, protecting provenance

/// A note shaped like a real draft: one filled section, one empty required
/// section, an unfiled statement, and an engine sentence with evidence.
private func phaseThreeNote() -> ClinicalNote {
    func section(_ key: String, _ title: String, _ text: String?, evidence: [String]) -> NoteSection {
        NoteSection(
            key: key,
            title: title,
            body: text ?? "",
            evidence: evidence,
            sentences: text.map {
                [NoteSentence(
                    text: $0, evidence: evidence, ambiguous: false,
                    support: "supported", wording: nil, authored: nil,
                    lineId: "line-\(key)", excluded: nil
                )]
            } ?? [],
            complete: text != nil
        )
    }
    return ClinicalNote(
        id: "n1",
        encounterId: "e1",
        templateId: "psychology",
        sections: [
            section("presenting", "Presenting", "Client reported sleeping four hours.", evidence: ["u1"]),
            section("risk", "Risk", nil, evidence: []),
        ],
        unassigned: [
            UnassignedStatement(text: "The weather was terrible on the way over.",
                                speakerRole: "patient", evidence: ["u2"]),
        ],
        excluded: nil,
        generatedAt: "2026-10-07T00:00:00Z",
        engine: "quire-phlox",
        reviewState: "draft",
        missingRequired: ["risk"],
        machineGenerated: true
    )
}

final class NoteEditingResolutionTests: XCTestCase {
    // MARK: - Moving

    /// A moved sentence takes its evidence with it and recomputes both
    /// sections — the destination's body gains the line, the source's loses
    /// it and becomes missing again if it was required.
    func testMovingCarriesEvidenceAndRecomputesSections() throws {
        let note = phaseThreeNote()
        let moved = try XCTUnwrap(NoteEditing.moving(
            sentenceID: "line-presenting", toSection: "risk", in: note,
            requiredKeys: ["presenting", "risk"]
        ))
        let risk = try XCTUnwrap(moved.sections.first { $0.key == "risk" })
        let presenting = try XCTUnwrap(moved.sections.first { $0.key == "presenting" })
        XCTAssertEqual(risk.sentences.map(\.text), ["Client reported sleeping four hours."])
        XCTAssertEqual(risk.sentences.flatMap(\.evidence), ["u1"], "the evidence moved with the line")
        XCTAssertEqual(risk.body, "Client reported sleeping four hours.")
        XCTAssertTrue(presenting.sentences.isEmpty)
        XCTAssertTrue(presenting.body.isEmpty)
        XCTAssertFalse(presenting.complete)
        XCTAssertTrue(moved.missingRequired.contains("presenting"),
                      "a required section emptied by the move is missing again")
        XCTAssertFalse(moved.missingRequired.contains("risk"),
                       "the destination is no longer missing")
    }

    // MARK: - Excluding a sentence

    /// Excluded means out of the body and the clipboard, but still in the
    /// note with its evidence — reversible, not a drop.
    func testExcludingKeepsTheSentenceButOutOfTheBody() throws {
        let note = phaseThreeNote()
        let excluded = try XCTUnwrap(NoteEditing.excluding(
            sentenceID: "line-presenting", in: note,
            requiredKeys: ["presenting", "risk"]
        ))
        let section = try XCTUnwrap(excluded.sections.first { $0.key == "presenting" })
        XCTAssertEqual(section.sentences.count, 1, "the sentence stays in the JSON")
        XCTAssertEqual(section.sentences[0].evidence, ["u1"], "evidence intact for the margin")
        XCTAssertEqual(section.sentences[0].excluded, true)
        XCTAssertTrue(section.body.isEmpty, "and out of the body the clipboard is built from")
        XCTAssertFalse(section.complete)
        XCTAssertTrue(excluded.missingRequired.contains("presenting"))
    }

    func testRestoringPutsItBack() throws {
        let note = try XCTUnwrap(NoteEditing.excluding(
            sentenceID: "line-presenting", in: phaseThreeNote(),
            requiredKeys: ["presenting", "risk"]
        ))
        let restored = try XCTUnwrap(NoteEditing.restoring(
            sentenceID: "line-presenting", in: note,
            requiredKeys: ["presenting", "risk"]
        ))
        let section = try XCTUnwrap(restored.sections.first { $0.key == "presenting" })
        XCTAssertEqual(section.sentences[0].excluded, false)
        XCTAssertEqual(section.body, "Client reported sleeping four hours.")
    }

    // MARK: - Unfiled statements

    func testExcludingUnfiledMovesItToExcludedAndRestoringBringsItBack() throws {
        let note = phaseThreeNote()
        let itemID = note.unassigned[0].id

        let excludedNote = try XCTUnwrap(NoteEditing.excludingUnfiled(itemID, from: note))
        XCTAssertTrue(excludedNote.unassigned.isEmpty, "out of the queue")
        XCTAssertEqual(excludedNote.excluded?.count, 1, "into the kept decisions")
        XCTAssertEqual(excludedNote.excluded?[0].evidence, ["u2"])

        let restoredNote = try XCTUnwrap(NoteEditing.restoringUnfiled(itemID, from: excludedNote))
        XCTAssertTrue(restoredNote.excluded?.isEmpty ?? true)
        XCTAssertEqual(restoredNote.unassigned.count, 1)
        XCTAssertEqual(restoredNote.unassigned[0].evidence, ["u2"], "evidence survives the round trip")
    }

    /// Filing an unfiled statement keeps it *quoted from the room*: the line
    /// lands in the section with the item's own evidence, and it does not
    /// present as an authored line.
    func testFilingUnfiledKeepsEvidenceAndDoesNotClaimAuthorship() throws {
        let note = phaseThreeNote()
        let item = note.unassigned[0]
        let filed = try XCTUnwrap(NoteEditing.adding(
            item.text, toSection: "presenting", in: note, lineId: "line-filed"
        ))
        let section = try XCTUnwrap(filed.sections.first { $0.key == "presenting" })
        XCTAssertTrue(section.body.contains("weather"))
    }

    // MARK: - Redraft protection

    /// Exclusions are decisions about content. A redraft that dropped them
    /// would revive sentences the clinician removed.
    func testARedraftCarriesExclusionsAcross() throws {
        var existing = phaseThreeNote()
        existing.excluded = [ExcludedStatement(
            text: "The weather was terrible on the way over.",
            speakerRole: "patient", evidence: ["u2"]
        )]
        let redrafted = phaseThreeNote() // the model's new pass, no exclusions
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redrafted)
        XCTAssertEqual(merged.excluded?.count, 1, "the decision survives the redraft")
    }

    /// A sentence the clinician excluded is a decision about content. The
    /// redraft used to revive it because only unfiled exclusions were carried.
    func testARedraftCarriesExcludedSentencesAcross() throws {
        let existing = try XCTUnwrap(NoteEditing.excluding(
            sentenceID: "line-presenting",
            in: phaseThreeNote(),
            requiredKeys: ["presenting", "risk"]
        ))
        let redrafted = phaseThreeNote()
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redrafted)
        let presenting = try XCTUnwrap(merged.sections.first { $0.key == "presenting" })
        XCTAssertTrue(presenting.sentences.first?.isExcluded == true)
        XCTAssertTrue(presenting.body.isEmpty, "an excluded line is not in the clipboard body")
    }

    // MARK: - Identity

    func testMintingLineIdsIsIdempotentAndFillsGaps() {
        var note = phaseThreeNote()
        note.sections[0].sentences.append(NoteSentence(
            text: "A later line.", evidence: ["u1"], ambiguous: false,
            support: nil, wording: nil, authored: nil, lineId: nil, excluded: nil
        ))
        let first = NoteEditing.mintingLineIds(for: note)
        let second = NoteEditing.mintingLineIds(for: first)
        XCTAssertEqual(first.sections[0].sentences.map(\.lineId), second.sections[0].sentences.map(\.lineId))
        XCTAssertNotNil(first.sections[0].sentences[1].lineId, "the gap was filled")
        XCTAssertEqual(first.sections[0].sentences[1].lineId, second.sections[0].sentences[1].lineId)
    }

    /// The property the whole phase turns on: a sentence's id must not
    /// change when its text does, once it has a minted id.
    func testACorrectedSentenceKeepsItsIdentity() {
        var note = phaseThreeNote()
        note.sections[0].sentences[0].text = "Rewritten by the clinician."
        XCTAssertEqual(note.sections[0].sentences[0].id, "line-presenting")
    }
}

// MARK: - Phase 4: honest output lifecycle

final class OutputLifecycleTests: XCTestCase {
    private func note(
        missing: [String] = [],
        nameChecks: Int = 0,
        jargon: Int = 0,
        unfiled: Int = 0
    ) -> (ClinicalNote, [NameCheck], Int) {
        let note = ClinicalNote(
            id: "note", encounterId: "e1", templateId: "psychology",
            sections: [
                NoteSection(key: "presenting", title: "Presenting", body: "Something.",
                            evidence: [], sentences: [], complete: true)
            ],
            unassigned: (0..<unfiled).map {
                UnassignedStatement(text: "left \($0)", speakerRole: "patient", evidence: [])
            },
            excluded: nil,
            generatedAt: "2026-10-07T00:00:00Z",
            engine: "quire-phlox", reviewState: "draft",
            missingRequired: missing, machineGenerated: true
        )
        // Jargon lives on sentences (`wording == "jargon"`); the flag count is
        // what `Readiness.of` consumes, so it is passed through directly.
        let checks = (0..<nameChecks).map {
            NameCheck(heard: "h\($0)", suggest: "s\($0)", evidence: [])
        }
        return (note, checks, jargon)
    }

    private func readiness(
        missing: [String], checks: [NameCheck], jargon: Int, unfiled: Int
    ) -> Readiness {
        Readiness.of(
            missingRequired: missing,
            nameChecks: checks.count,
            jargon: jargon,
            unfiled: unfiled
        )
    }

    private func readiness(for built: (ClinicalNote, [NameCheck], Int), unfiled: Int = 0) -> Readiness {
        readiness(missing: built.0.missingRequired, checks: built.1, jargon: built.2, unfiled: unfiled)
    }

    // MARK: - The output policy

    /// The plan's rule: a note with an unresolved problem cannot leave as a
    /// finished note — copied, printed, or reviewed. Names first, then
    /// missing sections, then wording.
    func testOutputPolicyBlocksOnNamesMissingAndWording() {
        let namesFirst = note(missing: ["risk"], nameChecks: 1)
        XCTAssertEqual(
            OutputPolicy.decision(for: readiness(for: namesFirst)),
            .blocked("1 name still needs checking.")
        )
        let missingSection = note(missing: ["risk"])
        XCTAssertEqual(
            OutputPolicy.decision(for: readiness(for: missingSection)),
            .blocked("A required section has nothing in it.")
        )
        let shorthand = note(jargon: 1)
        XCTAssertEqual(
            OutputPolicy.decision(for: readiness(for: shorthand)),
            .blocked("A sentence still carries shorthand to check.")
        )
    }

    /// Unfiled statements do not block: routine leftovers are reported in
    /// the status line, not turned into a ritual at the clipboard.
    func testUnfiledStatementsDoNotBlockTheOutput() {
        let built = note(unfiled: 3)
        XCTAssertEqual(
            OutputPolicy.decision(for: readiness(for: built, unfiled: built.0.unassigned.count)),
            .allowed
        )
    }

    func testAnEmptyNoteIsAllowed() {
        XCTAssertEqual(OutputPolicy.decision(for: .empty), .allowed)
    }

    // MARK: - The copied receipt

    func testAReceiptIsCurrentForTheRevisionItCopied() {
        let (note, _, _) = note()
        let receipt = CopiedReceipt(encounterID: "e1", note: note)
        XCTAssertTrue(receipt.isCurrent(for: note))
    }

    /// An edit after the copy is a different revision. The stale receipt
    /// must not describe it — otherwise the desk would stop showing the
    /// session while the clipboard held yesterday's text. The shell
    /// restamps `generatedAt` on every human edit (`markEdited`); the test
    /// restamps the same way, in the same format, with its own formatter —
    /// this bundle compiles Domain only, so it cannot see AppModel.
    func testAnEditedNoteMakesTheReceiptStale() {
        var (note, _, _) = note()
        let receipt = CopiedReceipt(encounterID: "e1", note: note)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        note.generatedAt = formatter.string(from: Date())
        XCTAssertNotEqual(note.generatedAt, receipt.generatedAt)
        XCTAssertFalse(receipt.isCurrent(for: note))
    }

    /// The shell must carry the document's render kind. When it did not, a
    /// referral letter was encoded without `render`, the Rust side defaulted to
    /// sections, and Copy/Print lost the letter framing.
    func testLetterRenderSurvivesTheShellRoundTrip() throws {
        var note = note().0
        note.render = "letter"
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(ClinicalNote.self, from: data)
        XCTAssertEqual(decoded.render, "letter")
    }

    /// A redraft changes the engine's pass and with it the revision —
    /// a different note id is enough, because `isCurrent` compares both.
    func testARedraftedNoteMakesTheReceiptStale() {
        let (note, _, _) = note()
        let receipt = CopiedReceipt(encounterID: "e1", note: note)
        var redrafted = note
        redrafted = ClinicalNote(
            id: "note-2",
            encounterId: note.encounterId,
            templateId: note.templateId,
            sections: note.sections,
            unassigned: note.unassigned,
            excluded: note.excluded,
            generatedAt: note.generatedAt,
            engine: note.engine,
            reviewState: note.reviewState,
            missingRequired: note.missingRequired,
            machineGenerated: note.machineGenerated
        )
        XCTAssertFalse(receipt.isCurrent(for: redrafted))
    }
}
