import XCTest

/// The decisions the shell makes about a consult. No app, no store, no
/// Keychain, no UI — these are functions over values.
extension DecisionsTests {
    // MARK: - Writing a line into an empty section

    /// Build a note with one filled section and three the engine left empty —
    /// the shape a 15-second recording actually produces.
    private func partiallyFilledNote() -> ClinicalNote {
        func section(_ key: String, _ title: String, _ body: String, required: Bool) -> NoteSection {
            NoteSection(
                key: key,
                title: title,
                body: body,
                evidence: [],
                sentences: body.isEmpty
                    ? []
                    : [NoteSentence(text: body, evidence: ["u1"], ambiguous: false,
                                    support: "supported", wording: nil)],
                complete: !required || !body.isEmpty
            )
        }
        return ClinicalNote(
            id: "n1",
            encounterId: "e1",
            templateId: "soap",
            sections: [
                section("subjective", "Subjective", "Sore throat for four days.", required: true),
                section("objective", "Objective", "", required: true),
                section("assessment", "Assessment", "", required: true),
                section("plan", "Plan", "", required: true),
            ],
            unassigned: [],
            generatedAt: "2026-09-11T00:00:00Z",
            engine: "quire-phlox",
            reviewState: "draft",
            missingRequired: ["objective", "assessment", "plan"],
            machineGenerated: true
        )
    }

    // MARK: - A redraft must not delete the clinician's own lines

    /// A note the model has just written again: same template, different prose,
    /// and — the point — none of the clinician's lines, because they were never
    /// in the transcript it read.
    private func redraftedNote() -> ClinicalNote {
        var note = partiallyFilledNote()
        note = ClinicalNote(
            id: note.id,
            encounterId: note.encounterId,
            templateId: note.templateId,
            sections: note.sections.map { section in
                var copy = section
                copy.sentences = [
                    NoteSentence(
                        text: "Model prose for \(section.key).",
                        evidence: ["u-model"],
                        ambiguous: false,
                        support: "supported",
                        wording: "plain"
                    )
                ]
                copy.body = copy.sentences.map(\.text).joined(separator: " ")
                copy.complete = true
                return copy
            },
            unassigned: note.unassigned,
            generatedAt: note.generatedAt,
            engine: "quire-phlox",
            reviewState: note.reviewState,
            missingRequired: [],
            machineGenerated: note.machineGenerated
        )
        return note
    }

    func testARedraftKeepsTheLineTheClinicianTyped() {
        // The model never saw it, so it cannot reproduce it, so replacing the
        // note deleted it — silently, and with the record marked "Edited".
        let withNote = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )
        let existing = withNote!
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redraftedNote())

        let objective = merged.sections.first { $0.key == "objective" }
        XCTAssertEqual(objective?.sentences.last?.text, "Chest clear.")
        XCTAssertEqual(objective?.sentences.last?.isAuthored, true)
        // The model's prose is still there; this is a merge, not a revert.
        XCTAssertEqual(objective?.sentences.first?.text, "Model prose for objective.")
    }

    func testARestoredLineReachesTheBodySoTheClipboardCarriesIt() {
        let existing = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )!
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redraftedNote())
        let body = merged.sections.first { $0.key == "objective" }?.body ?? ""
        XCTAssertTrue(body.contains("Chest clear."), body)
        XCTAssertTrue(body.contains("Model prose for objective."), body)
    }

    func testARestoredLineFillsASectionTheModelLeftEmpty() {
        var redrafted = redraftedNote()
        let index = redrafted.sections.firstIndex { $0.key == "plan" }!
        redrafted.sections[index].sentences = []
        redrafted.sections[index].body = ""
        redrafted.sections[index].complete = false
        redrafted.missingRequired = ["plan"]

        let existing = NoteEditing.adding(
            "Review in a week.", toSection: "plan", in: partiallyFilledNote(), lineId: "line-2"
        )!
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redrafted)
        let plan = merged.sections.first { $0.key == "plan" }
        XCTAssertEqual(plan?.complete, true)
        XCTAssertEqual(plan?.body, "Review in a week.")
        XCTAssertFalse(merged.missingRequired.contains("plan"))
    }

    func testMergingTwiceDoesNotMultiplyTheLine() {
        // The paste path and the download notification can both land, and a
        // merge of a merge must not grow the note.
        let existing = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )!
        let once = NoteEditing.carryingAuthoredLines(from: existing, into: redraftedNote())
        let twice = NoteEditing.carryingAuthoredLines(from: once, into: once)
        let lines = twice.sections.first { $0.key == "objective" }?.sentences
            .filter { $0.text == "Chest clear." } ?? []
        XCTAssertEqual(lines.count, 1)
    }

    func testMergingLeavesModelSentencesAlone() {
        let existing = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )!
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: redraftedNote())
        let section = merged.sections.first { $0.key == "objective" }!
        XCTAssertEqual(section.sentences.filter(\.isAuthored).count, 1)
        XCTAssertEqual(section.sentences.filter { !$0.isAuthored }.count, 1)
    }

    func testALineIsNotMovedIntoASectionItWasNotWrittenFor() {
        // A different template is a different question. Putting a line into a
        // section that was not written for it would be worse than leaving it out.
        let existing = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )!
        var other = redraftedNote()
        other.sections.removeAll { $0.key == "objective" }
        let merged = NoteEditing.carryingAuthoredLines(from: existing, into: other)
        XCTAssertFalse(merged.sections.contains { $0.key == "objective" })
        XCTAssertFalse(
            merged.sections.contains { $0.sentences.contains { $0.text == "Chest clear." } },
            "the line must not be invented into another section"
        )
    }

    func testANoteKnowsWhetherTheRulesWroteIt() {
        // The letterhead, the prompt and the redraft all key off this. A note
        // written by the rules used to read exactly like a model-written one,
        // which is how a clinician ends up trusting the worse draft.
        var note = partiallyFilledNote()
        XCTAssertFalse(note.wasWrittenByRules, "the fixture is written by a model")
        note = ClinicalNote(
            id: note.id,
            encounterId: note.encounterId,
            templateId: note.templateId,
            sections: note.sections,
            unassigned: note.unassigned,
            generatedAt: note.generatedAt,
            engine: "rule-based-v1",
            reviewState: note.reviewState,
            missingRequired: note.missingRequired,
            machineGenerated: note.machineGenerated
        )
        XCTAssertTrue(note.wasWrittenByRules)
    }

    func testAddingALineFillsTheSectionAndClearsItFromMissing() {
        let note = partiallyFilledNote()
        let updated = NoteEditing.adding(
            "Chest clear on auscultation.",
            toSection: "objective",
            in: note,
            lineId: "line-1"
        )
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.missingRequired, ["assessment", "plan"])
        let objective = updated?.sections.first { $0.key == "objective" }
        XCTAssertEqual(objective?.complete, true)
        XCTAssertEqual(objective?.sentences.count, 1)
    }

    func testAnAddedLineIsFoldedIntoTheBodySoCopyCarriesIt() {
        // The clipboard is built from `body`. A line on screen but not in the
        // body would be missing from what gets pasted into the record.
        let updated = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )
        XCTAssertEqual(updated?.sections.first { $0.key == "objective" }?.body, "Chest clear.")
    }

    func testAnAddedLineDoesNotDisturbOtherSections() {
        let updated = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )
        XCTAssertEqual(
            updated?.sections.first { $0.key == "subjective" }?.body,
            "Sore throat for four days."
        )
    }

    func testAddingNothingIsANoOpSoNothingIsPersisted() {
        for empty in ["", "   ", "\n\t "] {
            XCTAssertNil(
                NoteEditing.adding(empty, toSection: "objective",
                                   in: partiallyFilledNote(), lineId: "line-1"),
                "whitespace must not become a line"
            )
        }
    }

    func testAddingToASectionThatDoesNotExistIsRefused() {
        XCTAssertNil(
            NoteEditing.adding("x", toSection: "nonsense",
                               in: partiallyFilledNote(), lineId: "line-1")
        )
    }

    func testAnAddedLineIsMarkedAsWrittenByAPerson() {
        let updated = NoteEditing.adding(
            "Chest clear.", toSection: "objective", in: partiallyFilledNote(), lineId: "line-1"
        )
        let line = updated?.sections.first { $0.key == "objective" }?.sentences.first
        XCTAssertEqual(line?.isAuthored, true)
        XCTAssertEqual(line?.evidence, [])
        // Not "supported": nothing verified it. Not "unverified" either, which
        // would put a warning on the clinician's own words.
        XCTAssertNil(line?.support)
    }

    func testTwoIdenticalWrittenLinesDoNotShareAnId() {
        // "Nil." in two sections is normal clinical writing. Under the
        // evidence-based id both would be "none::Nil." and selecting one would
        // select both.
        let once = NoteEditing.adding("Nil.", toSection: "objective",
                                      in: partiallyFilledNote(), lineId: "line-1")
        let twice = once.flatMap {
            NoteEditing.adding("Nil.", toSection: "plan", in: $0, lineId: "line-2")
        }
        let ids = twice?.sections.flatMap(\.sentences).filter(\.isAuthored).map(\.id) ?? []
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2, "two lines, two identities")
    }

    func testAnAddedLineMakesTheNoteCountAsReady() {
        // The whole point: after writing the missing sections the note is no
        // longer stuck reporting something missing.
        var note = partiallyFilledNote()
        for key in ["objective", "assessment", "plan"] {
            note = NoteEditing.adding("Written.", toSection: key, in: note, lineId: key) ?? note
        }
        XCTAssertTrue(note.missingRequired.isEmpty)
        XCTAssertTrue(
            Readiness.of(missingRequired: note.missingRequired, nameChecks: 0,
                         jargon: 0, unfiled: 0).isPasteReady
        )
    }
}

final class DecisionsTests: XCTestCase {

    // MARK: - Helpers

    private func note(
        sections: [(String, String)],
        missing: [String] = [],
        checks: [NameCheck] = [],
        unfiled: Int = 0
    ) -> (ClinicalNote, Transcript) {
        let encounterId = UUID().uuidString
        var transcript = Transcript(
            encounterId: encounterId,
            speakers: [],
            segments: [],
            language: "en",
            engine: "test",
            humanSupplied: true,
            createdAt: nil
        )
        transcript.nameChecks = checks.isEmpty ? nil : checks

        let note = ClinicalNote(
            id: "note",
            encounterId: encounterId,
            templateId: "soap",
            sections: sections.map { key, body in
                NoteSection(
                    key: key,
                    title: key.capitalized,
                    body: body,
                    evidence: [],
                    sentences: body.isEmpty ? [] : [
                        NoteSentence(text: body, evidence: [], ambiguous: false,
                                     support: "supported", wording: "plain")
                    ],
                    complete: !body.isEmpty
                )
            },
            unassigned: (0..<unfiled).map {
                UnassignedStatement(
                    text: "unfiled \($0)",
                    speakerRole: "clinician",
                    evidence: []
                )
            },
            generatedAt: "2026-09-11T10:00:00Z",
            engine: "rule-based-v1",
            reviewState: "draft",
            missingRequired: missing,
            machineGenerated: true
        )
        return (note, transcript)
    }

    private func encounter(
        id: String = UUID().uuidString,
        ref: String = "enc-1",
        startedAt: Date = Date(),
        clinician: String? = nil,
        state: NoteState = .draft,
        note: ClinicalNote? = nil,
        transcript: Transcript? = nil
    ) -> Encounter {
        Encounter(
            id: id,
            patientRef: ref,
            discipline: "general_practice",
            templateId: "soap",
            startedAt: startedAt,
            state: state,
            note: note,
            transcript: transcript,
            clinicianRef: clinician,
            isSyntheticDemo: false
        )
    }

    // MARK: - Readiness

    func testReadinessPutsNamesBeforeMissingSections() {
        // A wrong drug is worse than a missing paragraph.
        let readiness = Readiness.of(
            missingRequired: ["plan"], nameChecks: 2, jargon: 1, unfiled: 4
        )
        XCTAssertEqual(readiness, .namesToCheck(2))
        XCTAssertFalse(readiness.isPasteReady)
    }

    func testReadinessReportsMissingBeforeWording() {
        XCTAssertEqual(
            Readiness.of(missingRequired: ["plan"], nameChecks: 0, jargon: 3, unfiled: 0),
            .missingRequired
        )
    }

    func testReadinessIsReadyOnceNothingBlocks() {
        let readiness = Readiness.of(
            missingRequired: [], nameChecks: 0, jargon: 0, unfiled: 7
        )
        XCTAssertEqual(readiness, .ready(unfiled: 7))
        XCTAssertTrue(readiness.isPasteReady)
        // Conversational leftovers are reported, not treated as a problem.
        XCTAssertEqual(readiness.label, "Ready · 7 not filed")
    }

    func testCompletenessLineNamesTheMissingSections() {
        // "Missing something required" makes the clinician go looking.
        let line = Readiness.completenessLine(
            sections: 4,
            filled: 3,
            missingTitles: ["Plan"],
            readiness: .missingRequired
        )
        XCTAssertEqual(line, "3 of 4 sections · missing: Plan")
    }

    func testCompletenessLineCountsNamesToCheck() {
        let line = Readiness.completenessLine(
            sections: 4,
            filled: 4,
            missingTitles: [],
            readiness: .namesToCheck(2)
        )
        XCTAssertEqual(line, "4 of 4 sections · 2 names to check")
    }

    func testReadinessLabelsAreSingularForOne() {
        XCTAssertEqual(Readiness.namesToCheck(1).label, "1 name to check")
        XCTAssertEqual(Readiness.namesToCheck(3).label, "3 names to check")
    }

    // MARK: - The copy guard

    func testCopyIsAllowedWhenTheConsultIsOnScreen() {
        XCTAssertEqual(
            CopyGuard.decision(requested: "a", selection: "a", isOnScreen: true, hasNote: true),
            .allowed
        )
    }

    func testCopyAsksWhenTheConsultIsNotOnScreen() {
        // The whole point: the clipboard never moves blind.
        XCTAssertEqual(
            CopyGuard.decision(requested: "a", selection: "b", isOnScreen: true, hasNote: true),
            .confirm
        )
        XCTAssertEqual(
            CopyGuard.decision(requested: "a", selection: "a", isOnScreen: false, hasNote: true),
            .confirm
        )
    }

    func testCopyWithNothingToCopy() {
        XCTAssertEqual(
            CopyGuard.decision(requested: "a", selection: "a", isOnScreen: true, hasNote: false),
            .nothingToCopy
        )
    }

    // MARK: - Tasks

    func testOpenRowsExcludeDoneAndOrphans() {
        let first = UUID().uuidString
        let second = UUID().uuidString
        let tasks = [
            ConsultTask(id: "1", encounterId: first, text: "Arrange a swab",
                        sourceKey: "plan", createdAt: "t", done: false),
            ConsultTask(id: "2", encounterId: first, text: "Review in a week",
                        sourceKey: "plan", createdAt: "t", done: true),
            ConsultTask(id: "3", encounterId: second, text: "Refer to ENT",
                        sourceKey: "plan", createdAt: "t", done: false),
            ConsultTask(id: "4", encounterId: "gone", text: "Orphan",
                        sourceKey: "plan", createdAt: "t", done: false),
        ]
        let rows = TaskViews.openRows(
            tasks: tasks,
            encounters: [encounter(id: first), encounter(id: second)]
        )
        XCTAssertEqual(rows.map(\.task.id), ["1", "3"])
    }

    func testTaskIndexIsKeyedBySentenceAndScopedToTheConsult() {
        let mine = UUID().uuidString
        let other = UUID().uuidString
        let tasks = [
            ConsultTask(id: "1", encounterId: mine, text: "Arrange a swab",
                        sourceKey: "plan", createdAt: "t", done: false),
            ConsultTask(id: "2", encounterId: mine, text: "Review in a week",
                        sourceKey: "plan", createdAt: "t", done: true),
            ConsultTask(id: "3", encounterId: other, text: "Not mine",
                        sourceKey: "plan", createdAt: "t", done: false),
        ]
        let index = TaskViews.index(tasks: tasks, encounterID: mine)
        XCTAssertEqual(Set(index.keys), ["Arrange a swab", "Review in a week"])
        // A ticked task still resolves, so the letter can show it struck through.
        XCTAssertEqual(index["Review in a week"]?.done, true)
        XCTAssertNil(index["Not mine"])
        XCTAssertTrue(TaskViews.index(tasks: tasks, encounterID: nil).isEmpty)
    }

    // MARK: - The board

    /// The invariant the perf fix rests on: one read in, everything out.
    func testBoardDerivesEverythingFromOneRead() {
        let mine = UUID().uuidString
        let other = UUID().uuidString
        let tasks = [
            ConsultTask(id: "1", encounterId: mine, text: "Arrange a swab",
                        sourceKey: "plan", createdAt: "t", done: false),
            ConsultTask(id: "2", encounterId: mine, text: "Review in a week",
                        sourceKey: "plan", createdAt: "t", done: true),
            ConsultTask(id: "3", encounterId: other, text: "Refer to ENT",
                        sourceKey: "plan", createdAt: "t", done: false),
        ]
        let board = TaskBoard.build(
            tasks: tasks,
            encounters: [encounter(id: mine), encounter(id: other)],
            selection: mine
        )
        // The still-to-do list is open tasks only.
        XCTAssertEqual(board.openRows.map(\.task.id), ["1", "3"])
        XCTAssertEqual(board.openCount, 2)
        // The index is the selected consult's, and includes what is done so the
        // letter can strike it through.
        XCTAssertEqual(Set(board.index.keys), ["Arrange a swab", "Review in a week"])
        XCTAssertEqual(board.task(for: "Review in a week", in: mine)?.done, true)
        XCTAssertNil(board.task(for: "Refer to ENT", in: mine))
    }

    func testBoardWithNoSelectionHasNoIndex() {
        let board = TaskBoard.build(tasks: [], encounters: [], selection: nil)
        XCTAssertTrue(board.index.isEmpty)
        XCTAssertEqual(board.openCount, 0)
    }

    func testMovingSelectionMovesTheIndex() {
        let first = UUID().uuidString
        let second = UUID().uuidString
        let tasks = [
            ConsultTask(id: "1", encounterId: first, text: "One",
                        sourceKey: "plan", createdAt: "t", done: false),
            ConsultTask(id: "2", encounterId: second, text: "Two",
                        sourceKey: "plan", createdAt: "t", done: false),
        ]
        let encounters = [encounter(id: first), encounter(id: second)]
        XCTAssertEqual(
            TaskBoard.build(tasks: tasks, encounters: encounters, selection: first).index.keys.sorted(),
            ["One"]
        )
        XCTAssertEqual(
            TaskBoard.build(tasks: tasks, encounters: encounters, selection: second).index.keys.sorted(),
            ["Two"]
        )
    }

    // MARK: - Grouping

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    func testGroupsAreNewestFirstAndLabelled() {
        let groups = EncounterGrouping.groups(
            from: [encounter(startedAt: day(-1)), encounter(startedAt: day(0))],
            matching: "",
            today: Date()
        )
        XCTAssertEqual(groups.map(\.day), ["Today", "Yesterday"])
    }

    func testSearchLooksAtTheWordsThatWereSaid() {
        let (note, _) = note(sections: [("subjective", "sore throat")])
        let withWords = encounter(note: note)

        XCTAssertTrue(EncounterGrouping.matches(withWords, needle: "sore throat"))
        XCTAssertTrue(EncounterGrouping.matches(withWords, needle: "enc-1"))
        XCTAssertFalse(EncounterGrouping.matches(withWords, needle: "angina"))

        let groups = EncounterGrouping.groups(
            from: [withWords], matching: "angina", today: Date()
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testSearchIgnoresCaseAndSurroundingSpace() {
        let groups = EncounterGrouping.groups(
            from: [encounter(ref: "enc-ABC")], matching: "  abc ", today: Date()
        )
        XCTAssertEqual(groups.count, 1)
    }

    func testSharedMacShowsOnlyMyConsultsButNeverHidesUnsignedOnes() {
        let mine = encounter(ref: "mine", clinician: "Dr A")
        let theirs = encounter(ref: "theirs", clinician: "Dr B")
        let unattributed = encounter(ref: "old", clinician: nil)

        let scoped = EncounterGrouping.groups(
            from: [mine, theirs, unattributed],
            matching: "",
            today: Date(),
            clinician: "Dr A"
        )
        let refs = scoped.flatMap { $0.encounters.map(\.patientRef) }.sorted()
        // Hiding a note is worse than showing one that is not mine.
        XCTAssertEqual(refs, ["mine", "old"])

        let all = EncounterGrouping.groups(
            from: [mine, theirs, unattributed],
            matching: "",
            today: Date(),
            clinician: "Dr A",
            showAllClinicians: true
        )
        XCTAssertEqual(all.flatMap { $0.encounters }.count, 3)
    }

    // MARK: - Learned vocabulary

    func testLearnedTermsRewriteEveryOccurrenceCaseInsensitively() {
        let (text, hits) = LearnedTermRewriting.rewrite(
            "atyrazine in the morning, AtYrazine at night",
            using: ["atyrazine": "cetirizine"]
        )
        XCTAssertEqual(text, "cetirizine in the morning, cetirizine at night")
        XCTAssertEqual(hits, 2)
    }

    func testLearnedTermsLeaveOtherWordsAlone() {
        let (text, hits) = LearnedTermRewriting.rewrite(
            "I take cetirizine for hay fever",
            using: ["cetirizine": "cetirizine"]
        )
        XCTAssertEqual(hits, 1)
        XCTAssertTrue(text.contains("hay fever"))
    }

    /// The rule a replacement may not be re-scanned by itself. This failed on
    /// the first run of this suite: the old implementation searched the text it
    /// was rewriting, so `cetir` → `cetirizine` matched its own output and ran
    /// to a twenty-iteration cap, producing `cetirizineizineizine…`.
    func testReplacementIsNeverRescanned() {
        let (text, hits) = LearnedTermRewriting.rewrite(
            "cetir for hay fever",
            using: ["cetir": "cetirizine"]
        )
        XCTAssertEqual(text, "cetirizine for hay fever")
        XCTAssertEqual(hits, 1)
        XCTAssertFalse(text.contains("izineizine"))
    }

    func testLongestTermWinsOnOverlap() {
        let (text, _) = LearnedTermRewriting.rewrite(
            "panadol soluble",
            using: ["panadol soluble": "paracetamol soluble", "panadol": "paracetamol"]
        )
        XCTAssertEqual(text, "paracetamol soluble")
    }

    func testApplyingVocabularyClearsTheChecksItResolves() {
        var transcript = Transcript(
            encounterId: "e",
            speakers: [],
            segments: [
                TranscriptSegment(id: "s1", speaker: 0, startMs: 0, endMs: 1,
                                  text: "I take atyrazine", confidence: nil)
            ],
            language: "en",
            engine: "whisper",
            humanSupplied: false,
            createdAt: nil
        )
        transcript.nameChecks = [
            NameCheck(heard: "atyrazine", suggest: "cetirizine", evidence: ["s1"]),
            NameCheck(heard: "saterazine", suggest: "cetirizine", evidence: ["s1"]),
        ]

        let (fixed, applied) = LearnedTermRewriting.apply(
            to: transcript, using: ["atyrazine": "cetirizine"]
        )
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(fixed.segments.first?.text, "I take cetirizine")
        // Asking again about a term the practice has settled is noise.
        XCTAssertEqual(fixed.nameChecks?.map(\.heard), ["saterazine"])
    }

    func testEmptyVocabularyIsANoOp() {
        let transcript = Transcript(
            encounterId: "e", speakers: [], segments: [], language: "en",
            engine: "w", humanSupplied: false, createdAt: nil
        )
        let (same, applied) = LearnedTermRewriting.apply(to: transcript, using: [:])
        XCTAssertEqual(applied, 0)
        XCTAssertEqual(same.segments.count, transcript.segments.count)
    }
}
