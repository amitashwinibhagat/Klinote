//
// CopyConfirmSheet.swift
//
// The wrong-consult guard.
//
// Copy note is one keystroke, and pasting the wrong patient's note into a
// record is the failure a clinician would actually fear. Copying what is
// already on screen needs no confirmation — the letterhead is right there.
// Copying something else does, and this sheet says exactly what the clipboard
// is about to hold.
//

import SwiftUI

struct CopyConfirmSheet: View {
    let encounter: Encounter
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var firstLine: String {
        let line = encounter.note?.sections
            .first { !$0.body.trimmingCharacters(in: .whitespaces).isEmpty }?
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(140) ?? "No documented sections."
        return String(line)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Text("Copy this consult?")
                .font(KlinoteFont.panelHeading())
                .foregroundStyle(KlinoteColor.primary)
            Text("This is not the consult the window was showing. Check it is the right one before you paste.")
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
                Field(label: "Reference", value: encounter.patientRef)
                Field(label: "Consult", value: EncounterSpine.time(encounter.startedAt))
                Field(label: "Document", value: model.displayName(for: encounter))
            }

            VStack(alignment: .leading, spacing: KlinoteMetrics.space4) {
                TabLabel(text: "Starts with")
                Text(firstLine)
                    .font(KlinoteFont.documentMinor())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(KlinoteMetrics.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KlinoteColor.recessed)
            .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy this one") {
                    model.copySelectedNote()
                    dismiss()
                }
                .buttonStyle(KlinotePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(KlinoteMetrics.sheetInset)
        .frame(width: KlinoteMetrics.sheetWidth)
        .background(KlinoteColor.document)
    }
}
