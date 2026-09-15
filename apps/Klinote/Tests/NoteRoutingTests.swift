import XCTest

/// Where an extracted statement lands.
///
/// Every case here is a mistake a real run produced — the model filed the
/// examination under Assessment and repeated it in Objective; it filed the
/// impression and all four plan statements under Assessment and offered Plan
/// nothing at all. The bench found them; these keep them found, without needing
/// a language model, Apple Intelligence, or four minutes of synthesis to run.
final class NoteRoutingTests: XCTestCase {
    /// The SOAP fields, with abbreviated real cues from `templates/soap.toml`.
    private let soapCues: [[String]] = [
        // 0 subjective
        ["sore throat", "hurts", "tired", "fever", "history", "medication", "allergies"],
        // 1 objective
        ["temperature", "pulse", "on examination", "erythema", "chest", "auscultation"],
        // 2 assessment
        ["impression", "likely", "viral", "infection", "differential"],
        // 3 plan
        ["plan", "mg", "rest", "fluids", "swab", "come back", "safety net", "arrange"],
    ]

    private func claim(_ text: String, chose: Int) -> NoteRouting.Claim {
        NoteRouting.Claim(modelChose: chose, text: text)
    }

    // MARK: - A statement can move

    /// The plan statement was offered under Assessment and nowhere else. With no
    /// rival claim, de-duplicating cannot help — it has to move.
    func testAPlanStatementFiledUnderAssessmentMovesToPlan() {
        let claims = [claim(
            "Plan: rest and plenty of fluids, paracetamol 1g four times a day as needed for pain",
            chose: 2
        )]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [3], "the plan's own cues should claim it")
    }

    /// And the impression must not follow it there.
    func testAnImpressionStaysInAssessment() {
        let claims = [claim(
            "My impression is a viral upper respiratory tract infection, most likely viral tonsillopharyngitis",
            chose: 2
        )]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [2])
    }

    /// The examination findings were filed under Assessment *and* under
    /// Objective. Objective has to keep them.
    func testAnExaminationFiledUnderAssessmentMovesToObjective() {
        let claims = [claim(
            "On examination today your temperature is 37.4, pulse 88 and regular",
            chose: 2
        )]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [1])
    }

    // MARK: - It moves only on a clear mismatch

    /// A statement that matches nothing anywhere keeps the model's choice. A
    /// routing decision made on no evidence is worse than the model's guess.
    func testAStatementWithNoCueMatchStaysWhereTheModelPutIt() {
        let claims = [claim("I'll also send you a link about self-care", chose: 1)]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [1])
    }

    /// One cue's worth of difference is a coin flip, and the model's reading of
    /// the sentence beats a coin flip.
    func testAMarginalScoreDoesNotMoveAStatement() {
        // Matches "mg" in plan (1) and "pulse" in objective (1): a tie.
        let claims = [claim("pulse 88, 400mg", chose: 1)]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [1], "a tie keeps the model's field")
    }

    // MARK: - One statement, one field

    func testTheSameStatementOfferedTwiceIsKeptOnce() {
        let text = "On examination today your temperature is 37.4"
        let claims = [
            claim(text, chose: 2),  // assessment, wrong
            claim(text, chose: 1),  // objective, right
        ]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations.filter { $0 != nil }.count, 1, "kept once")
        // Which claim survives is a tie between identical words, so it cannot
        // matter — but what it survives *as* can. Both moved to Objective, so
        // the note must show the finding there and nowhere else.
        XCTAssertEqual(destinations.compactMap { $0 }, [1])
    }

    /// Ties between duplicates go to the first claim, so the answer does not
    /// depend on the order the model answered the fields in.
    func testDuplicateTieKeepsTheFirstClaim() {
        let text = "I'll also send you a link about self-care"
        let claims = [claim(text, chose: 0), claim(text, chose: 3)]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations[0], 0)
        XCTAssertEqual(destinations[1], nil)
    }

    // MARK: - Degenerate input

    func testNoClaimsResolvesToNothing() {
        XCTAssertEqual(NoteRouting.resolve(claims: [], sectionCues: soapCues), [])
    }

    func testNoSectionsResolvesEverythingToNothing() {
        let claims = [claim("anything", chose: 0)]
        XCTAssertEqual(NoteRouting.resolve(claims: claims, sectionCues: []), [nil])
    }

    /// A model index outside the template must not trap or silently drop.
    func testAnOutOfRangeModelChoiceFallsBackToTheBestMatch() {
        let claims = [claim("Plan: rest and fluids", chose: 99)]
        let destinations = NoteRouting.resolve(claims: claims, sectionCues: soapCues)
        XCTAssertEqual(destinations, [3])
    }

    // MARK: - Scoring

    func testCueScoreCountsEachCueOnce() {
        let score = NoteRouting.cueScore("Plan: rest, fluids, and rest again", cues: ["plan", "rest", "fluids"])
        XCTAssertEqual(score, 3, "a repeated word is still one cue")
    }

    func testCueScoreIgnoresCaseAndEmptyCues() {
        XCTAssertEqual(NoteRouting.cueScore("PLAN: Rest", cues: ["plan", "rest", ""]), 2)
    }
}
