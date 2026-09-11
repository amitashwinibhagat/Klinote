//
// DocumentView.swift
//
// The note as a working document: letterhead, ruled sections, unfiled
// statements, signature block. Every sentence carries a margin reference so it
// can be traced to what was said.
//

import AppKit
import SwiftUI

struct DocumentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let encounter = model.selectedEncounter,
               let note = encounter.note,
               let transcript = encounter.transcript {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Letterhead(encounter: encounter, note: note)
                        ForEach(note.sections) { section in
                            SectionBlock(section: section, model: model)
                        }
                        if !note.unassigned.isEmpty {
                            UnfiledBlock(items: note.unassigned)
                        }
                        SignatureBlock(model: model, note: note)
                    }
                    .frame(width: KlinoteMetrics.documentMeasure, alignment: .leading)
                    .padding(KlinoteMetrics.space32)
                    .background(KlinoteColor.document)
                    .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous)
                            .strokeBorder(KlinoteColor.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .padding(KlinoteMetrics.space32)
                    .frame(maxWidth: .infinity)
                    .environment(\.openURL, OpenURLAction { _ in .handled })
                    .id(transcript.encounterId)
                    .animation(.easeOut(duration: KlinoteMetrics.motionAssemble), value: transcript.encounterId)
                }
                .background(KlinoteColor.desk)
            } else if let error = model.lastError {
                EmptyState(title: "Could not write this note", message: error)
                    .padding(KlinoteMetrics.space48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(KlinoteColor.desk)
            } else {
                EmptyState(
                    title: "No note selected",
                    message: "Choose a consult, or record one."
                )
                .padding(KlinoteMetrics.space48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KlinoteColor.desk)
            }
        }
    }
}

// MARK: - Letterhead

struct Letterhead: View {
    let encounter: Encounter
    let note: ClinicalNote

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            Text("klinote")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(KlinoteColor.ink)
            HStack(alignment: .firstTextBaseline) {
                Text(templateTitle)
                    .font(KlinoteFont.document(19, weight: .semibold))
                    .foregroundStyle(KlinoteColor.primary)
                Spacer(minLength: KlinoteMetrics.space16)
                Text(encounter.patientRef)
                    .font(KlinoteFont.data(11))
                    .foregroundStyle(KlinoteColor.secondary)
            }

            HStack(spacing: KlinoteMetrics.space24) {
                Field(label: "Recorded", value: EncounterSpine.time(encounter.startedAt))
                Field(label: "Duration", value: durationLabel)
                Field(label: "Status", value: readinessLabel)
            }

            ProvisionanceLine(note: note, isSynthetic: encounter.isSyntheticDemo)

            LetterheadRule()
                .padding(.top, KlinoteMetrics.space4)
        }
        .padding(.bottom, KlinoteMetrics.space24)
    }

    private var templateTitle: String {
        note.templateId == "soap" ? "Clinical note" : "\(note.templateId.capitalized) note"
    }

    private var durationLabel: String {
        guard let ms = encounter.durationMs else { return "—" }
        return RecordingStripView.clock(Double(ms) / 1000)
    }

    private var readinessLabel: String {
        if !note.unassigned.isEmpty {
            return "\(note.unassigned.count) unfiled"
        }
        if !note.missingRequired.isEmpty {
            return "Missing required"
        }
        return "Ready to copy"
    }
}

struct Field: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FieldLabel(text: label)
            Text(value)
                .font(KlinoteFont.data(11))
                .foregroundStyle(KlinoteColor.primary)
        }
    }
}

/// Always visible. If the text is synthetic, the document says so.
struct ProvisionanceLine: View {
    let note: ClinicalNote
    let isSynthetic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Written on this Mac. Nothing left the device.")
                .font(KlinoteFont.label())
                .foregroundStyle(KlinoteColor.tertiary)
            if isSynthetic {
                Text("Sample text — not a real consult.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.caution)
                Text("Click a sentence to see the words that produced it.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sections

struct SectionBlock: View {
    let section: NoteSection
    @ObservedObject var model: AppModel

    private var state: SectionState {
        if !section.complete { return .missingRequired }
        if section.sentences.isEmpty { return .emptyOptional }
        return .filled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            SectionHeader(title: section.title, state: state)

            if section.sentences.isEmpty {
                Text("Not documented.")
                    .font(KlinoteFont.document(14))
                    .foregroundStyle(KlinoteColor.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(section.sentences.enumerated()), id: \.element.id) { index, sentence in
                        SentenceRow(
                            sentence: sentence,
                            number: index + 1,
                            isSelected: model.selectedSentenceID == sentence.id
                        ) {
                            model.selectedSentenceID =
                                model.selectedSentenceID == sentence.id ? nil : sentence.id
                        }
                    }
                }
            }
        }
        .padding(.bottom, KlinoteMetrics.space32)
    }
}

/// A sentence with its margin reference. The reference is a number, not a
/// colour, so it survives a monochrome display and a colour-blind reader.
struct SentenceRow: View {
    let sentence: NoteSentence
    let number: Int
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
            Text(sentence.ambiguous ? "\(number)?" : "\(number)")
                .font(KlinoteFont.data(9))
                .foregroundStyle(isSelected ? KlinoteColor.ink : KlinoteColor.tertiary)
                .frame(width: 18, alignment: .trailing)

            Text(sentence.text)
                .font(KlinoteFont.document(14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(KlinoteColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? KlinoteColor.accent.opacity(0.14)
                : hovering ? KlinoteColor.accent.opacity(0.06) : Color.clear
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? KlinoteColor.ink : hovering ? KlinoteColor.ink.opacity(0.35) : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .animation(.easeOut(duration: KlinoteMetrics.motionState), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Sentence \(number)\(sentence.ambiguous ? ", source unclear" : "")"
        )
        .accessibilityHint("Shows the words this sentence came from")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Unfiled statements

/// Above the signature block, never below it and never hidden: these are what
/// the clinician must resolve before signing.
struct UnfiledBlock: View {
    let items: [UnassignedStatement]

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            SectionHeader(title: "Not filed to a section", state: .missingRequired)
            Text("Heard, not placed. File them or drop them before you sign.")
                .font(KlinoteFont.ui(12))
                .foregroundStyle(KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                    Text(item.speakerRole.uppercased())
                        .font(KlinoteFont.label(9, weight: .semibold))
                        .foregroundStyle(KlinoteColor.tertiary)
                        .frame(width: 62, alignment: .leading)
                    Text(item.text)
                        .font(KlinoteFont.document(13))
                        .foregroundStyle(KlinoteColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, KlinoteMetrics.space32)
    }
}

// MARK: - Signature block

struct SignatureBlock: View {
    @ObservedObject var model: AppModel
    let note: ClinicalNote

    private var isReviewed: Bool { model.selectedEncounter?.state == .approved }
    private var canSwap: Bool {
        guard let encounter = model.selectedEncounter else { return false }
        return !encounter.isSyntheticDemo && (encounter.transcript?.speakers.count ?? 0) >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Hairline()

            HStack(alignment: .bottom, spacing: KlinoteMetrics.space24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReviewed ? "Reviewed by you" : "Not yet reviewed")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.secondary)
                    Text(isReviewed ? "Just now, on this Mac" : "Copy the note, then mark it reviewed.")
                        .font(KlinoteFont.document(14))
                        .foregroundStyle(KlinoteColor.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: KlinoteMetrics.space8) {
                    Text(model.completenessLine)
                        .font(KlinoteFont.ui(12))
                        .foregroundStyle(
                            note.missingRequired.isEmpty ? KlinoteColor.secondary : KlinoteColor.caution
                        )
                        .multilineTextAlignment(.trailing)

                    HStack(spacing: KlinoteMetrics.space8) {
                        if canSwap {
                            Button {
                                model.swapSpeakersAndRedraft()
                            } label: {
                                Text(model.isSwapping ? "Swapping…" : "Swap speakers")
                            }
                            .controlSize(.small)
                            .disabled(model.isSwapping)
                            .help("Swap clinician and patient, then rebuild the note (⌥⌘S)")
                        }
                        Button {
                            model.copySelectedNote()
                        } label: {
                            Text(model.isCopying ? "Copied" : "Copy note")
                        }
                        .controlSize(.small)
                        .help("Copy the note to paste into the record (⌘⇧C)")
                        Button {
                            model.fileSelectedNote()
                        } label: {
                            Text(model.isFiling ? "Saving…" : "Mark as reviewed")
                        }
                        .buttonStyle(KlinotePrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.isFiling || isReviewed)
                        .help("Mark this draft as reviewed on this Mac (⌘↩)")
                    }
                }
            }

            Text("Copy note puts it on the clipboard. Mark as reviewed stays on this Mac. Nothing is sent.")
                .font(KlinoteFont.label())
                .foregroundStyle(KlinoteColor.tertiary)
        }
        .padding(.top, KlinoteMetrics.space8)
    }
}
