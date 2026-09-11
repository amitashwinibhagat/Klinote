//
// PasteTranscriptSheet.swift
//
// The zero-download path: paste what was said, get a note. Nothing here needs
// a model, a network, or a recording.
//

import SwiftUI

struct PasteTranscriptSheet: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Text("Paste a transcript")
                .font(KlinoteFont.panelHeading())
                .foregroundStyle(KlinoteColor.primary)
            Text("One line per turn, starting with CLINICIAN: or PATIENT:. No audio and no download — the note is written on this Mac.")
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(KlinoteFont.documentMinor())
                .frame(minHeight: KlinoteMetrics.sheetMinHeight)
                .padding(KlinoteMetrics.space8)
                .background(KlinoteColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous)
                        .strokeBorder(KlinoteColor.hairline, lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Make the note") {
                    model.makeNote(fromPastedText: text)
                    dismiss()
                }
                .buttonStyle(KlinotePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(KlinoteMetrics.sheetInset)
        .frame(width: KlinoteMetrics.sheetWidth)
        .background(KlinoteColor.document)
    }
}
