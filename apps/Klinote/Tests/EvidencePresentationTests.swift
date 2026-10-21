import XCTest

/// Which words the margin shows. The product's trust move is "select a
/// sentence, see the words that produced it"; these pin the filtering rule
/// so the column cannot quietly become a transcript again.
final class EvidencePresentationTests: XCTestCase {
    private func segment(_ id: String, at start: UInt64, _ text: String) -> TranscriptSegment {
        TranscriptSegment(id: id, speaker: 0, startMs: start, endMs: start + 1000,
                          text: text, confidence: nil)
    }

    private var consultation: [TranscriptSegment] {
        [
            segment("u1", at: 0, "First words."),
            segment("u2", at: 1000, "Second words."),
            segment("u3", at: 2000, "Third words."),
        ]
    }

    /// Selected mode answers with the cited segments alone — not the whole
    /// consultation with a highlight in it.
    func testSelectedModeShowsOnlyTheCitedWords() {
        let visible = EvidencePresentation.visible(
            segments: consultation, citing: ["u3"], mode: .selected
        )
        XCTAssertEqual(visible.map(\.id), ["u3"])
    }

    /// Citations come back in the order they were said, whatever order the
    /// note sentence lists them in.
    func testSelectedModeSortsByTime() {
        let visible = EvidencePresentation.visible(
            segments: consultation, citing: ["u3", "u1"], mode: .selected
        )
        XCTAssertEqual(visible.map(\.id), ["u1", "u3"])
    }

    /// Nothing selected is nothing shown. An empty citation list must not
    /// fall back to the transcript: that is how the column stops being an
    /// answer and starts being homework.
    func testNoSelectionShowsNothing() {
        XCTAssertTrue(
            EvidencePresentation.visible(segments: consultation, citing: [], mode: .selected).isEmpty
        )
    }

    /// A human-written line cites nothing, and full mode is still the whole
    /// session on request.
    func testFullModeReturnsEverySegment() {
        let visible = EvidencePresentation.visible(
            segments: consultation, citing: [], mode: .full
        )
        XCTAssertEqual(visible.map(\.id), ["u1", "u2", "u3"])
    }

    /// A citation the transcript does not contain is counted, so the header
    /// can say a source is missing instead of rendering "no source" as if it
    /// were normal.
    func testMissingCitationsAreCounted() {
        XCTAssertEqual(
            EvidencePresentation.missingCitations(segments: consultation, citing: ["u1", "gone"]),
            1
        )
        XCTAssertEqual(
            EvidencePresentation.missingCitations(segments: consultation, citing: ["u1", "u2"]),
            0
        )
    }
}
