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
                    .frame(width: NotaMetrics.documentMeasure, alignment: .leading)
                    .padding(NotaMetrics.space32)
                    .background(NotaColor.document)
                    .clipShape(RoundedRectangle(cornerRadius: NotaMetrics.radiusDocument, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotaMetrics.radiusDocument, style: .continuous)
                            .strokeBorder(NotaColor.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .padding(NotaMetrics.space32)
                    .frame(maxWidth: .infinity)
                    .environment(\.openURL, OpenURLAction { _ in .handled })
                    .id(transcript.encounterId)
                }
                .background(NotaColor.desk)
            } else if let error = model.lastError {
                EmptyState(title: "The engine could not draft this note", message: error)
                    .padding(NotaMetrics.space48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NotaColor.desk)
            } else {
                EmptyState(
                    title: "No note selected",
                    message: "Choose an encounter, or record a consultation to draft a new note."
                )
                .padding(NotaMetrics.space48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NotaColor.desk)
            }
        }
    }
}

// MARK: - Letterhead

struct Letterhead: View {
    let encounter: Encounter
    let note: ClinicalNote

    var body: some View {
        VStack(alignment: .leading, spacing: NotaMetrics.space12) {
            HStack(alignment: .firstTextBaseline) {
                Text(templateTitle)
                    .font(NotaFont.document(19, weight: .semibold))
                    .foregroundStyle(NotaColor.primary)
                Spacer(minLength: NotaMetrics.space16)
                Text(encounter.patientRef)
                    .font(NotaFont.data(11))
                    .foregroundStyle(NotaColor.secondary)
            }

            HStack(spacing: NotaMetrics.space24) {
                Field(label: "Encounter", value: String(encounter.id.prefix(8)))
                Field(label: "Recorded", value: EncounterSpine.time(encounter.startedAt))
                Field(label: "Duration", value: durationLabel)
                Field(label: "Draft", value: encounter.state.word)
            }

            ProvisionanceLine(note: note, isSynthetic: encounter.isSyntheticDemo)

            LetterheadRule()
                .padding(.top, NotaMetrics.space4)
        }
        .padding(.bottom, NotaMetrics.space24)
    }

    private var templateTitle: String {
        note.templateId == "soap" ? "Clinical note" : "\(note.templateId.capitalized) note"
    }

    private var durationLabel: String {
        guard let ms = encounter.durationMs else { return "—" }
        return RecordingStripView.clock(Double(ms) / 1000)
    }
}

struct Field: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FieldLabel(text: label)
            Text(value)
                .font(NotaFont.data(11))
                .foregroundStyle(NotaColor.primary)
        }
    }
}

/// Always visible. If the text is synthetic, the document says so.
struct ProvisionanceLine: View {
    let note: ClinicalNote
    let isSynthetic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Drafted on this Mac · engine \(note.engine) · nothing left the device")
                .font(NotaFont.label())
                .foregroundStyle(NotaColor.tertiary)
            if isSynthetic {
                Text("Synthetic sample text — not a real transcription.")
                    .font(NotaFont.label())
                    .foregroundStyle(NotaColor.caution)
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
        VStack(alignment: .leading, spacing: NotaMetrics.space12) {
            SectionHeader(title: section.title, state: state)

            if section.sentences.isEmpty {
                Text("Not documented.")
                    .font(NotaFont.document(14))
                    .foregroundStyle(NotaColor.tertiary)
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
        .padding(.bottom, NotaMetrics.space32)
    }
}

/// A sentence with its margin reference. The reference is a number, not a
/// colour, so it survives a monochrome display and a colour-blind reader.
struct SentenceRow: View {
    let sentence: NoteSentence
    let number: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NotaMetrics.space8) {
            Text(sentence.ambiguous ? "\(number)?" : "\(number)")
                .font(NotaFont.data(9))
                .foregroundStyle(isSelected ? NotaColor.ink : NotaColor.tertiary)
                .frame(width: 18, alignment: .trailing)

            Text(sentence.text)
                .font(NotaFont.document(14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(NotaColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? NotaColor.accent.opacity(0.14) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? NotaColor.ink : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
        VStack(alignment: .leading, spacing: NotaMetrics.space12) {
            SectionHeader(title: "Not filed to a section", state: .missingRequired)
            Text("These statements were heard but could not be placed with confidence. File them or discard them before signing.")
                .font(NotaFont.ui(12))
                .foregroundStyle(NotaColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: NotaMetrics.space8) {
                    Text(item.speakerRole.uppercased())
                        .font(NotaFont.label(9, weight: .semibold))
                        .foregroundStyle(NotaColor.tertiary)
                        .frame(width: 62, alignment: .leading)
                    Text(item.text)
                        .font(NotaFont.document(13))
                        .foregroundStyle(NotaColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, NotaMetrics.space32)
    }
}

// MARK: - Signature block

struct SignatureBlock: View {
    @ObservedObject var model: AppModel
    let note: ClinicalNote

    var body: some View {
        VStack(alignment: .leading, spacing: NotaMetrics.space16) {
            Hairline()

            HStack(alignment: .bottom, spacing: NotaMetrics.space24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reviewed and signed by")
                        .font(NotaFont.label())
                        .foregroundStyle(NotaColor.secondary)
                    Text("—")
                        .font(NotaFont.document(15))
                        .foregroundStyle(NotaColor.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.completenessLine)
                        .font(NotaFont.ui(12))
                        .foregroundStyle(
                            note.missingRequired.isEmpty ? NotaColor.secondary : NotaColor.caution
                        )
                        .multilineTextAlignment(.trailing)
                    Button {
                        model.fileSelectedNote()
                    } label: {
                        Text(model.isFiling ? "Filing…" : "File note")
                    }
                    .buttonStyle(NotaPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isFiling || model.selectedEncounter?.state == .approved)
                    .help("File this note into the record (⌘↩)")
                }
            }

            Text("Filing records your approval. The draft itself is machine-generated and is never filed without this action.")
                .font(NotaFont.label())
                .foregroundStyle(NotaColor.tertiary)
        }
        .padding(.top, NotaMetrics.space8)
    }
}
