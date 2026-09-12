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
    /// Evidence answers "why is this in my note?". The whole consultation
    /// answers "what did we actually say?", which is what a clinician asks
    /// when a complaint or a re-referral arrives months later.
    @State private var showingWholeConsult = false
    @State private var transcriptSearch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            if let transcript = model.selectedEncounter?.transcript {
                Picker("", selection: $showingWholeConsult) {
                    Text("Evidence").tag(false)
                    Text("Full").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Show evidence for the selected sentence, or the whole session")
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.bottom, KlinoteMetrics.space8)

                if showingWholeConsult {
                    HStack(spacing: KlinoteMetrics.inline6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: KlinoteMetrics.iconSmall))
                            .foregroundStyle(KlinoteColor.tertiary)
                        TextField("Search the words", text: $transcriptSearch)
                            .textFieldStyle(.plain)
                            .font(KlinoteFont.caption())
                    }
                    .padding(.horizontal, KlinoteMetrics.space8)
                    .padding(.vertical, KlinoteMetrics.inline6)
                    .background(KlinoteColor.recessed)
                    .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                    .padding(.horizontal, KlinoteMetrics.space16)
                    .padding(.bottom, KlinoteMetrics.space8)
                }

                if transcript.humanSupplied {
                    Text("This note came from typed text, not a recording.")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.tertiary)
                        .padding(.horizontal, KlinoteMetrics.space16)
                        .padding(.vertical, KlinoteMetrics.space8)
                } else {
                    voiceMapping(transcript)
                    Hairline()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visibleSegments(transcript)) { segment in
                                UtteranceRow(
                                    segment: segment,
                                    role: label(for: segment, in: transcript),
                                    isEvidence: !showingWholeConsult && evidenceIDs.contains(segment.id),
                                    isPrimary: !showingWholeConsult && primaryEvidenceID == segment.id
                                )
                                .id(segment.id)
                                Hairline()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    message: "Nothing to trace this note to yet."
                )
                .padding(KlinoteMetrics.space16)
                Spacer()
            }
        }
        .background(KlinoteColor.margin)
    }

    private func visibleSegments(_ transcript: Transcript) -> [TranscriptSegment] {
        guard showingWholeConsult, !transcriptSearch.isEmpty else {
            return transcript.segments
        }
        let needle = transcriptSearch.lowercased()
        return transcript.segments.filter { $0.text.lowercased().contains(needle) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space4) {
            TabLabel(text: showingWholeConsult ? "Whole session" : "Evidence")
            if showingWholeConsult {
                Text("\(model.selectedEncounter?.transcript?.segments.count ?? 0) things said. A gap marked held was not recorded.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            } else if let selected = selectedSentence, selected.sentence.isAuthored {
                // Nothing was said, so there is nothing to point at. Saying so
                // is the difference between "you wrote this" and a line that
                // looks like every other line.
                Text("You wrote this line")
                    .font(KlinoteFont.caption(.medium))
                    .foregroundStyle(KlinoteColor.primary)
                Text("It did not come from the recording, so there are no words behind it.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let sentenceNumber = selectedSentenceNumber {
                // Short, and allowed to wrap. This line is how a clinician
                // knows which sentence the margin is answering for, so it must
                // never be the thing that truncates.
                Text("Behind sentence \(sentenceNumber)")
                    .font(KlinoteFont.caption(.medium))
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Click any sentence to see the words that produced it.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// From a recording, diarisation yields anonymous voices — it does not know
    /// who the clinician is. Say so, rather than asserting a role we inferred.
    private func label(for segment: TranscriptSegment, in transcript: Transcript) -> String {
        if transcript.humanSupplied {
            return transcript.speakers.first { $0.id == segment.speaker }?.role ?? "other"
        }
        return "Voice \(Self.voiceLetter(segment.speaker))"
    }

    static func voiceLetter(_ speaker: UInt32) -> String {
        let scalar = UnicodeScalar(65 + Int(speaker))
        return scalar.map(String.init) ?? "?"
    }

    /// One line naming the assumption the routing made, with the one tap that
    /// corrects it. Only when there is more than one voice to confuse.
    @ViewBuilder
    private func voiceMapping(_ transcript: Transcript) -> some View {
        if !transcript.humanSupplied, transcript.speakers.count >= 2 {
            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                Text("Voice A → therapist · Voice B → client")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
                Spacer(minLength: 0)
                Button("Swap") { model.swapSpeakersAndRedraft() }
                    .controlSize(.small)
                    .disabled(model.isSwapping || model.isSynthetic)
                    .help("Swap therapist and client, then rebuild the note (⌥⌘S)")
            }
            .padding(.horizontal, KlinoteMetrics.space16)
            .padding(.vertical, KlinoteMetrics.space8)
        }
    }
}

struct UtteranceRow: View {
    let segment: TranscriptSegment
    let role: String
    let isEvidence: Bool
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space4) {
            HStack(spacing: KlinoteMetrics.space8) {
                Text(role.uppercased())
                    .font(KlinoteFont.micro())
                    .foregroundStyle(isEvidence ? KlinoteColor.ink : KlinoteColor.tertiary)
                Text(Self.timestamp(segment.startMs))
                    .font(KlinoteFont.microData())
                    .foregroundStyle(KlinoteColor.tertiary)
                Spacer(minLength: 0)
                if isPrimary {
                    Text("source")
                        .font(KlinoteFont.micro())
                        .foregroundStyle(KlinoteColor.ink)
                        .accessibilityHidden(true)
                }
            }
            Text(segment.text)
                .font(KlinoteFont.utterance(isEvidence ? .medium : .regular))
                .foregroundStyle(isEvidence ? KlinoteColor.primary : KlinoteColor.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KlinoteMetrics.space16)
        .padding(.vertical, KlinoteMetrics.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isEvidence ? KlinoteColor.accent.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isPrimary ? KlinoteColor.ink : Color.clear)
                .frame(width: KlinoteMetrics.ruleWidth)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPrimary
                ? "Source of the selected sentence. \(role) at \(Self.timestamp(segment.startMs)): \(segment.text)"
                : "\(role) at \(Self.timestamp(segment.startMs)): \(segment.text)"
        )
    }

    static func timestamp(_ ms: UInt64) -> String {
        let total = Int(ms / 1000)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
