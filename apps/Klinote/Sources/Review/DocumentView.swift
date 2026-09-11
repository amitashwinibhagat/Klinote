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
                        Letterhead(model: model, encounter: encounter, note: note)
                        ForEach(note.sections) { section in
                            SectionBlock(section: section, model: model)
                        }
                        if let checks = encounter.transcript?.nameChecks, !checks.isEmpty {
                            NameCheckBlock(checks: checks, model: model)
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
    @ObservedObject var model: AppModel
    let encounter: Encounter
    let note: ClinicalNote

    private var canSwap: Bool {
        !encounter.isSyntheticDemo && (encounter.transcript?.speakers.count ?? 0) >= 2
    }

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

            ProvisionanceLine(
                model: model,
                note: note,
                isSynthetic: encounter.isSyntheticDemo
            )

            if canSwap {
                Button {
                    model.swapSpeakersAndRedraft()
                } label: {
                    Text(model.isSwapping ? "Swapping voices…" : "Voices look wrong? Swap clinician and patient")
                }
                .buttonStyle(.plain)
                .font(KlinoteFont.ui(12))
                .foregroundStyle(KlinoteColor.ink)
                .disabled(model.isSwapping)
                .help("⌥⌘S")
            }

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

    /// Conversational leftovers must not mask readiness: a consult with seven
    /// "how are you today?" lines in unfiled is still ready to copy.
    private var readinessLabel: String {
        let names = encounter.transcript?.nameChecks?.count ?? 0
        if names > 0 {
            return names == 1 ? "1 name to check" : "\(names) names to check"
        }
        if !note.missingRequired.isEmpty {
            return "Missing required"
        }
        if model.jargonCount(for: note) > 0 {
            return "Check wording"
        }
        if !note.unassigned.isEmpty {
            return "Ready · \(note.unassigned.count) not filed"
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
    @ObservedObject var model: AppModel
    let note: ClinicalNote
    let isSynthetic: Bool

    private var isDocument: Bool {
        model.documentTemplates.contains { $0.id == note.templateId }
    }

    /// A letter written by the built-in rules is a rough draft, and saying so
    /// is more useful than letting the clinician discover it.
    private var engineLine: String {
        if note.engine.hasPrefix("rule-based") && isDocument {
            return "Rough draft from the built-in rules. The language model writes this document better."
        }
        return "Written on this Mac. Nothing left the device."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(engineLine)
                .font(KlinoteFont.label())
                .foregroundStyle(
                    note.engine.hasPrefix("rule-based") && isDocument
                        ? KlinoteColor.caution
                        : KlinoteColor.tertiary
                )
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
                        if model.editingSentenceID == sentence.id {
                            SentenceEditor(sentence: sentence, model: model)
                        } else {
                            SentenceRow(
                                sentence: sentence,
                                number: index + 1,
                                isSelected: model.selectedSentenceID == sentence.id,
                                onEdit: { model.editingSentenceID = sentence.id }
                            ) {
                                model.selectedSentenceID =
                                    model.selectedSentenceID == sentence.id ? nil : sentence.id
                            }
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
/// Correct one sentence. ⌘↩ saves, Escape cancels.
struct SentenceEditor: View {
    let sentence: NoteSentence
    @ObservedObject var model: AppModel
    @State private var draft: String
    @FocusState private var focused: Bool

    init(sentence: NoteSentence, model: AppModel) {
        self.sentence = sentence
        self.model = model
        _draft = State(initialValue: sentence.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
            TextEditor(text: $draft)
                .font(KlinoteFont.document(14))
                .focused($focused)
                .frame(minHeight: 56)
                .padding(KlinoteMetrics.space8)
                .background(KlinoteColor.document)
                .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous)
                        .strokeBorder(KlinoteColor.ink.opacity(0.4), lineWidth: 1)
                )
            HStack(spacing: KlinoteMetrics.space8) {
                Text("Correcting one sentence. The words in the margin are unchanged.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
                Spacer(minLength: 0)
                Button("Cancel") { model.editingSentenceID = nil }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.commitSentenceEdit(sentence.id, to: draft) }
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .onAppear { focused = true }
    }
}

struct SentenceRow: View {
    let sentence: NoteSentence
    let number: Int
    let isSelected: Bool
    var onEdit: () -> Void = {}
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

            if sentence.isJargon {
                Text("check wording")
                    .font(KlinoteFont.label(9, weight: .semibold))
                    .foregroundStyle(KlinoteColor.caution)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusChip, style: .continuous)
                            .strokeBorder(KlinoteColor.caution.opacity(0.5), lineWidth: 1)
                    )
                    .help("Clinical shorthand the patient would have to decode. Expanding it here could change an instruction.")
                    .fixedSize()
            } else if sentence.isUnverified {
                Text("check source")
                    .font(KlinoteFont.label(9, weight: .semibold))
                    .foregroundStyle(KlinoteColor.caution)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusChip, style: .continuous)
                            .strokeBorder(KlinoteColor.caution.opacity(0.5), lineWidth: 1)
                    )
                    .help("A figure or drug name here is not in the words that were heard.")
                    .fixedSize()
            }
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
        .onTapGesture(count: 2, perform: onEdit)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Correct this sentence…", action: onEdit)
            Button("Show the words behind it", action: onSelect)
        }
        .animation(.easeOut(duration: KlinoteMetrics.motionState), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Sentence \(number)\(sentence.ambiguous ? ", source unclear" : "")"
        )
        .accessibilityHint("Shows the words this sentence came from. Double-click to correct it.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Unfiled statements

/// Above the signature block, never below it and never hidden: these are what
struct NameCheckBlock: View {
    let checks: [NameCheck]
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            SectionHeader(title: "Check these names", state: .missingRequired)
            Text("Heard in the consult. Not replaced until you say so.")
                .font(KlinoteFont.ui(12))
                .foregroundStyle(KlinoteColor.secondary)
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                    Text("\(check.heard) → \(check.suggest)")
                        .font(KlinoteFont.document(13))
                        .foregroundStyle(KlinoteColor.primary)
                    Spacer(minLength: 0)
                    Button("Use \(check.suggest)") {
                        model.applyNameCheck(heard: check.heard, suggest: check.suggest)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.bottom, KlinoteMetrics.space32)
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Hairline()

            HStack(alignment: .bottom, spacing: KlinoteMetrics.space24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReviewed ? "Reviewed by you" : "Not yet reviewed")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.secondary)
                    Text(isReviewed ? "On this Mac. Not in the record until you paste." : "Paste into the record. Then mark reviewed here.")
                        .font(KlinoteFont.document(14))
                        .foregroundStyle(KlinoteColor.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: KlinoteMetrics.space8) {
                    Text(model.completenessLine)
                        .font(KlinoteFont.ui(12))
                        .foregroundStyle(
                            model.isPasteReady ? KlinoteColor.secondary : KlinoteColor.caution
                        )
                        .multilineTextAlignment(.trailing)

                    HStack(spacing: KlinoteMetrics.space8) {
                        Button {
                            model.fileSelectedNote()
                        } label: {
                            Text(model.isFiling ? "Saving…" : "Mark as reviewed")
                        }
                        .controlSize(.small)
                        .disabled(model.isFiling || isReviewed)
                        .help("Local only. Does not send anything (⌘↩)")
                        Button {
                            model.copySelectedNote()
                        } label: {
                            Text(model.isCopying ? "Copied" : "Copy note")
                        }
                        .buttonStyle(KlinotePrimaryButtonStyle())
                        .controlSize(.small)
                        .help("Copy the note to paste into the record (⌘⇧C)")
                    }
                }
            }

            Text("Double-click any sentence to correct it. Copy note is the path into the record; mark as reviewed stays on this Mac.")
                .font(KlinoteFont.label())
                .foregroundStyle(KlinoteColor.tertiary)
        }
        .padding(.top, KlinoteMetrics.space8)
    }
}
