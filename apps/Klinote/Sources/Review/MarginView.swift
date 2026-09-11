//
// MarginView.swift
//
// The evidence column. Select a sentence in the note and the words that
// produced it come forward — marked within the utterance, not just the whole
// line, so the clinician can see exactly which phrase carried the meaning.
//

import AppKit
import SwiftUI

struct MarginView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            if let transcript = model.selectedEncounter?.transcript {
                if transcript.humanSupplied {
                    Text("This draft was produced from a typed transcript, not a recording.")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.tertiary)
                        .padding(.horizontal, KlinoteMetrics.space16)
                        .padding(.vertical, KlinoteMetrics.space8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(transcript.segments) { segment in
                                UtteranceRow(
                                    segment: segment,
                                    role: role(for: segment, in: transcript),
                                    isEvidence: evidenceIDs.contains(segment.id),
                                    isPrimary: primaryEvidenceID == segment.id
                                )
                                .id(segment.id)
                                Hairline()
                            }
                        }
                    }
                    .onChange(of: model.selectedSentenceID) { _, _ in
                        guard let target = primaryEvidenceID else { return }
                        withAnimation(.easeInOut(duration: KlinoteMetrics.motionLayout)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            } else {
                EmptyState(
                    title: "No source",
                    message: "There is nothing to trace this note back to yet."
                )
                .padding(KlinoteMetrics.space16)
                Spacer()
            }
        }
        .background(KlinoteColor.margin)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TabLabel(text: "Evidence")
            if let sentenceNumber = selectedSentenceNumber {
                Text("Words behind sentence \(sentenceNumber)")
                    .font(KlinoteFont.ui(12, weight: .medium))
                    .foregroundStyle(KlinoteColor.primary)
            } else {
                Text("Select a sentence to see the words behind it.")
                    .font(KlinoteFont.ui(12))
                    .foregroundStyle(KlinoteColor.secondary)
            }
        }
        .padding(.horizontal, KlinoteMetrics.space16)
        .padding(.vertical, KlinoteMetrics.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Selection

    private var selectedSentence: (number: Int, sentence: NoteSentence)? {
        guard let note = model.selectedEncounter?.note, let id = model.selectedSentenceID else { return nil }
        for section in note.sections {
            for (index, sentence) in section.sentences.enumerated() where sentence.id == id {
                return (index + 1, sentence)
            }
        }
        return nil
    }

    private var selectedSentenceNumber: Int? { selectedSentence?.number }

    private var evidenceIDs: Set<String> {
        Set(selectedSentence?.sentence.evidence ?? [])
    }

    private var primaryEvidenceID: String? {
        selectedSentence?.sentence.evidence.first
    }

    private func role(for segment: TranscriptSegment, in transcript: Transcript) -> String {
        transcript.speakers.first { $0.id == segment.speaker }?.role ?? "other"
    }
}

struct UtteranceRow: View {
    let segment: TranscriptSegment
    let role: String
    let isEvidence: Bool
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: KlinoteMetrics.space8) {
                Text(role.uppercased())
                    .font(KlinoteFont.label(9, weight: .semibold))
                    .foregroundStyle(isEvidence ? KlinoteColor.ink : KlinoteColor.tertiary)
                Text(Self.timestamp(segment.startMs))
                    .font(KlinoteFont.data(10))
                    .foregroundStyle(KlinoteColor.tertiary)
                Spacer(minLength: 0)
                if isPrimary {
                    Text("source")
                        .font(KlinoteFont.label(9, weight: .semibold))
                        .foregroundStyle(KlinoteColor.ink)
                }
            }
            Text(segment.text)
                .font(KlinoteFont.ui(12.5, weight: isEvidence ? .medium : .regular))
                .foregroundStyle(isEvidence ? KlinoteColor.primary : KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KlinoteMetrics.space16)
        .padding(.vertical, KlinoteMetrics.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isEvidence ? KlinoteColor.accent.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isPrimary ? KlinoteColor.ink : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role) at \(Self.timestamp(segment.startMs)): \(segment.text)")
    }

    static func timestamp(_ ms: UInt64) -> String {
        let total = Int(ms / 1000)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
