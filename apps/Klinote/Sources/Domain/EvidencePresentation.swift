//
// EvidencePresentation.swift
//
// Which words the margin shows, as values.
//
// The margin's job is "I did not say that": the selected sentence's own
// evidence, immediately, without the clinician hunting through a transcript.
// The old behaviour put the whole consultation in the column and merely
// highlighted the cited lines, which made the highlight work that the reader
// had to do — the column was a transcript with a lighter line in it, not an
// answer.
//
// Two modes, and they are different jobs:
//
// * **selected** — the sentences the note line actually cites, in the order
//   they were said. Nothing else. No context is manufactured: a segment
//   there would be a quote the note does not cite, which is the opposite of
//   the product's claim.
// * **full** — the whole session, for "what did we actually say", search,
//   and the months-later question a complaint or a re-referral brings.
//
// Pure, so the filtering rule is testable without a window.
//

import Foundation

enum EvidencePresentation {
    enum Mode: Equatable {
        /// The cited words for the current selection.
        case selected
        /// Every segment of the consultation.
        case full
    }

    /// What the evidence column lists.
    ///
    /// - Parameters:
    ///   - segments: the consultation's segments, in transcript order.
    ///   - citing: segment ids the current selection cites.
    ///   - mode: the reader's chosen job.
    /// - Returns: for `.selected`, exactly the cited segments in time order —
    ///   empty when nothing is selected, so the view can say "click a
    ///   sentence" rather than showing an undifferentiated transcript. For
    ///   `.full`, every segment unchanged.
    static func visible(
        segments: [TranscriptSegment],
        citing: [String],
        mode: Mode
    ) -> [TranscriptSegment] {
        switch mode {
        case .full:
            return segments
        case .selected:
            let wanted = Set(citing)
            guard !wanted.isEmpty else { return [] }
            return segments
                .filter { wanted.contains($0.id) }
                .sorted { $0.startMs < $1.startMs }
        }
    }

    /// How many of a selection's citations are actually in the transcript.
    ///
    /// A citation the transcript does not contain is the one thing the
    /// margin must not hide: it would render as "no source" and read like an
    /// ordinary line. This count lets the header say so.
    static func missingCitations(
        segments: [TranscriptSegment],
        citing: [String]
    ) -> Int {
        let present = Set(segments.map(\.id))
        return citing.filter { !present.contains($0) }.count
    }
}
