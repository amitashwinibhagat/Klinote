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
                    .frame(
                        minWidth: KlinoteMetrics.documentMeasureMin,
                        idealWidth: KlinoteMetrics.documentMeasure,
                        maxWidth: KlinoteMetrics.documentMeasure,
                        alignment: .leading
                    )
                    .padding(KlinoteMetrics.space32)
                    .background(KlinoteColor.document)
                    .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous)
                            .strokeBorder(KlinoteColor.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .padding(KlinoteMetrics.space32)
                    // Explicitly centred. Left-aligned in a pane-filling frame
                    // left roughly four times as much dead desk on the right as
                    // on the left, which reads as an accident in a product
                    // whose argument is that it was made carefully.
                    .frame(maxWidth: .infinity, alignment: .center)
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
            BrandMark()
            HStack(alignment: .firstTextBaseline) {
                Text(templateTitle)
                    .font(KlinoteFont.documentTitle())
                    .foregroundStyle(KlinoteColor.primary)
                Spacer(minLength: KlinoteMetrics.space16)
                Text(encounter.patientRef)
                    .font(KlinoteFont.data())
                    .foregroundStyle(KlinoteColor.secondary)
            }

            HStack(spacing: KlinoteMetrics.space24) {
                Field(label: "Recorded", value: EncounterSpine.time(encounter.startedAt))
                Field(label: "Duration", value: durationLabel)
                Field(label: "Status", value: readinessLabel)
                if let held = encounter.transcript?.heldMs, held > 0 {
                    Field(
                        label: "Held",
                        value: RecordingStripView.clock(Double(held) / 1000)
                    )
                }
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
                .font(KlinoteFont.caption())
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
    /// One rule, one implementation. This was a second copy of the precedence
    /// in Readiness, which is how the two could drift apart unnoticed.
    private var readinessLabel: String {
        model.readiness(for: encounter).label
    }
}

struct Field: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
            FieldLabel(text: label)
            Text(value)
                .font(KlinoteFont.data())
                .foregroundStyle(KlinoteColor.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
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
        VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
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
            }
            // The "click a sentence" hint moved to the evidence margin, which
            // is what it is about. It was the sixth stacked line in the
            // letterhead, competing with the title for the first glance.
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSynthetic ? "\(engineLine) Sample text, not a real consult." : engineLine)
    }
}

// MARK: - Sections

struct SectionBlock: View {
    let section: NoteSection
    @ObservedObject var model: AppModel
    @State private var isAdding = false

    private var state: SectionState {
        if !section.complete { return .missingRequired }
        if section.sentences.isEmpty { return .emptyOptional }
        return .filled
    }

    private var encounterID: String { model.selectedEncounter?.id ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            SectionHeader(title: section.title, state: state)

            if section.sentences.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    Text("Not documented.")
                        .font(KlinoteFont.document())
                        .foregroundStyle(KlinoteColor.tertiary)
                    Spacer(minLength: 0)
                    if !isAdding {
                        Button("Write this section") { isAdding = true }
                            .controlSize(.small)
                            .accessibilityLabel("Write the \(section.title) section")
                    }
                }
                if !isAdding {
                    // Say why it is empty, so an empty section does not read as
                    // a failure. Quire writes from the recording; whatever the
                    // consult did not cover has to come from the clinician.
                    Text("Quire writes what it heard. Whatever this consult did not cover, write here.")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
                    ForEach(Array(section.sentences.enumerated()), id: \.element.id) { index, sentence in
                        if model.editingSentenceID == sentence.id {
                            SentenceEditor(sentence: sentence, model: model)
                        } else {
                            SentenceRow(
                                sentence: sentence,
                                number: index + 1,
                                isSelected: model.selectedSentenceID == sentence.id,
                                task: model.task(
                                    for: encounterID,
                                    sentence: sentence.text
                                ),
                                onToggleTask: { task in
                                    model.setTask(task, done: !task.done)
                                },
                                onEdit: { model.editingSentenceID = sentence.id }
                            ) {
                                model.selectedSentenceID =
                                    model.selectedSentenceID == sentence.id ? nil : sentence.id
                            }
                        }
                    }
                }
                if !isAdding {
                    Button("Add a line") { isAdding = true }
                        .controlSize(.small)
                        .accessibilityLabel("Add a line to \(section.title)")
                }
            }

            if isAdding {
                AddedLineEditor(section: section, model: model) { isAdding = false }
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
                .font(KlinoteFont.document())
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
        .padding(.vertical, KlinoteMetrics.space4)
        .padding(.horizontal, KlinoteMetrics.inline6)
        .onAppear { focused = true }
    }
}

/// The editor for a line the clinician adds. Deliberately plainer than the
/// correction editor: nothing was said, so there is no original to preserve and
/// no margin to point at.
struct AddedLineEditor: View {
    let section: NoteSection
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
            TextEditor(text: $draft)
                .font(KlinoteFont.document())
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
                Text("Your words. The margin will say you wrote them.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Cancel") { onClose() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if model.addSentence(toSection: section.key, text: draft) {
                        draft = ""
                        onClose()
                    }
                }
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, KlinoteMetrics.space4)
        .padding(.horizontal, KlinoteMetrics.inline6)
        .onAppear { focused = true }
    }
}

struct SentenceRow: View {
    let sentence: NoteSentence
    let number: Int
    let isSelected: Bool
    /// Present when this sentence is work to do — the consult's checklist.
    var task: ConsultTask?
    var onToggleTask: (ConsultTask) -> Void = { _ in }
    var onEdit: () -> Void = {}
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
            if let task {
                Button {
                    onToggleTask(task)
                } label: {
                    Image(systemName: task.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: KlinoteMetrics.iconRegular))
                        .foregroundStyle(task.done ? KlinoteColor.ink : KlinoteColor.tertiary)
                }
                .buttonStyle(.borderless)
                .help(task.done ? "Done. Click to reopen." : "Tick when you have done this.")
                .accessibilityLabel(task.done ? "ConsultTask done" : "ConsultTask not done")
            }
            Text(sentence.ambiguous ? "\(number)?" : "\(number)")
                .font(KlinoteFont.microNumber())
                .foregroundStyle(isSelected ? KlinoteColor.ink : KlinoteColor.tertiary)
                .frame(width: 18, alignment: .trailing)

            Text(sentence.text)
                .font(KlinoteFont.document(weight: isSelected ? .semibold : .regular))
                .foregroundStyle(KlinoteColor.primary)
                .strikethrough(task?.done == true, color: KlinoteColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if sentence.isJargon {
                Text("check wording")
                    .font(KlinoteFont.micro())
                    .foregroundStyle(KlinoteColor.caution)
                    .padding(.horizontal, KlinoteMetrics.radiusChip)
                    .padding(.vertical, KlinoteMetrics.inline2)
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusChip, style: .continuous)
                            .strokeBorder(KlinoteColor.caution.opacity(0.5), lineWidth: 1)
                    )
                    .help("Clinical shorthand the patient would have to decode. Expanding it here could change an instruction.")
                    .fixedSize()
            } else if sentence.isUnverified {
                Text("check source")
                    .font(KlinoteFont.micro())
                    .foregroundStyle(KlinoteColor.caution)
                    .padding(.horizontal, KlinoteMetrics.radiusChip)
                    .padding(.vertical, KlinoteMetrics.inline2)
                    .overlay(
                        RoundedRectangle(cornerRadius: KlinoteMetrics.radiusChip, style: .continuous)
                            .strokeBorder(KlinoteColor.caution.opacity(0.5), lineWidth: 1)
                    )
                    .help("A figure or drug name here is not in the words that were heard.")
                    .fixedSize()
            }
        }
        .padding(.vertical, KlinoteMetrics.inline2)
        .padding(.horizontal, KlinoteMetrics.inline6)
        .background(
            isSelected
                ? KlinoteColor.accent.opacity(0.14)
                : hovering ? KlinoteColor.accent.opacity(0.06) : Color.clear
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? KlinoteColor.ink : hovering ? KlinoteColor.ink.opacity(0.35) : Color.clear)
                .frame(width: KlinoteMetrics.ruleWidth)
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
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                    Text("\(check.heard) → \(check.suggest)")
                        .font(KlinoteFont.documentMinor())
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
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                    Text(item.speakerRole.uppercased())
                        .font(KlinoteFont.micro())
                        .foregroundStyle(KlinoteColor.tertiary)
                        .frame(width: 62, alignment: .leading)
                    Text(item.text)
                        .font(KlinoteFont.documentMinor())
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

    /// A note that says "reviewed by you" is not signed. Name the clinician,
    /// and their registration if they gave one, so a printed letter and a
    /// shared practice Mac both identify who is accountable.
    private var signatureLine: String {
        let name = model.clinicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        let registration = model.clinicianRegistration
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.isEmpty ? nil : name
        guard isReviewed else {
            return who.map { "Not yet reviewed — \($0)" } ?? "Not yet reviewed"
        }
        guard let who else { return "Reviewed on this Mac" }
        return registration.isEmpty
            ? "Reviewed by \(who)"
            : "Reviewed by \(who) · \(registration)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Hairline()

            HStack(alignment: .bottom, spacing: KlinoteMetrics.space24) {
                VStack(alignment: .leading, spacing: KlinoteMetrics.space4) {
                    Text(signatureLine)
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.secondary)
                    Text(isReviewed ? "On this Mac. Not in the record until you paste." : "Paste into the record. Then mark reviewed here.")
                        .font(KlinoteFont.document())
                        .foregroundStyle(KlinoteColor.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: KlinoteMetrics.space8) {
                    Text(model.completenessLine)
                        .font(KlinoteFont.caption())
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
