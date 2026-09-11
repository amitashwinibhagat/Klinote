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
                        .font(NotaFont.label())
                        .foregroundStyle(NotaColor.tertiary)
                        .padding(.horizontal, NotaMetrics.space16)
                        .padding(.vertical, NotaMetrics.space8)
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
                        withAnimation(.easeInOut(duration: NotaMetrics.motionLayout)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            } else {
                EmptyState(
                    title: "No source",
                    message: "There is nothing to trace this note back to yet."
                )
                .padding(NotaMetrics.space16)
                Spacer()
            }
        }
        .notaChromeSurface()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TabLabel(text: "Evidence")
            if let sentenceNumber = selectedSentenceNumber {
                Text("Words behind sentence \(sentenceNumber)")
                    .font(NotaFont.ui(12, weight: .medium))
                    .foregroundStyle(NotaColor.primary)
            } else {
                Text("Select a sentence to see the words behind it.")
                    .font(NotaFont.ui(12))
                    .foregroundStyle(NotaColor.secondary)
            }
        }
        .padding(.horizontal, NotaMetrics.space16)
        .padding(.vertical, NotaMetrics.space12)
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
            HStack(spacing: NotaMetrics.space8) {
                Text(role.uppercased())
                    .font(NotaFont.label(9, weight: .semibold))
                    .foregroundStyle(isEvidence ? NotaColor.ink : NotaColor.tertiary)
                Text(Self.timestamp(segment.startMs))
                    .font(NotaFont.data(10))
                    .foregroundStyle(NotaColor.tertiary)
                Spacer(minLength: 0)
                if isPrimary {
                    Text("source")
                        .font(NotaFont.label(9, weight: .semibold))
                        .foregroundStyle(NotaColor.ink)
                }
            }
            Text(segment.text)
                .font(NotaFont.ui(12.5, weight: isEvidence ? .medium : .regular))
                .foregroundStyle(isEvidence ? NotaColor.primary : NotaColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NotaMetrics.space16)
        .padding(.vertical, NotaMetrics.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isEvidence ? NotaColor.accent.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isPrimary ? NotaColor.ink : Color.clear)
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
