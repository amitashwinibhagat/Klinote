import XCTest

/// The decisions the shell makes about a consult. No app, no store, no
/// Keychain, no UI — these are functions over values.
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
