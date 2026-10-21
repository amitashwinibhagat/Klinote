//
// OutputRefusalSheet.swift
//
// A refused copy, print, or review — and the way past it.
//
// The old failure mode: Copy note silently produced an incomplete note, and
// the status line only *coloured differently* while doing it. The plan's §4-C
// answer is a gate, but a gate that only says no is a dead end for a
// clinician with a queue outside. So the refusal does three things, in the
// product's voice:
//
// * it names what is unresolved (never a code, never a scold);
// * it offers the jump — select the sentence in question, or focus the
//   missing section's editor;
// * for a required section the consult never covered, it offers the one
//   honest completion: the clinician's own words. It never writes "not
//   discussed" itself — the machine does not fill Risk.
//

import SwiftUI

struct OutputRefusalSheet: View {
    let pending: AppModel.PendingOutput
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var encounter: Encounter { pending.encounter }

    /// The first sentence carrying an unverified figure — the likeliest
    /// "check source" — so the jump lands somewhere useful.
    private var unverifiedSentenceID: String? {
        encounter.note?.sections
            .flatMap(\.sentences)
            .first { $0.isUnverified }?
            .id
    }

    /// The first missing required section, for the write-the-section jump.
    private var missingSection: NoteSection? {
        guard let key = encounter.note?.missingRequired.first else { return nil }
        return encounter.note?.sections.first { $0.key == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space16) {
            Text(title)
                .font(KlinoteFont.panelHeading())
                .foregroundStyle(KlinoteColor.primary)
            Text(pending.reason)
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.caution)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
                ForEach(jumps) { jump in
                    Button {
                        perform(jump)
                        dismiss()
                    } label: {
                        Label(jump.label, systemImage: jump.symbol)
                    }
                    .buttonStyle(.plain)
                    .font(KlinoteFont.ui())
                    .foregroundStyle(KlinoteColor.ink)
                }
            }

            Rule()

            Text("Nothing was copied, printed, or marked reviewed. The note is unchanged.")
                .font(KlinoteFont.label())
                .foregroundStyle(KlinoteColor.tertiary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(KlinoteMetrics.sheetInset)
        .frame(width: KlinoteMetrics.sheetWidth)
        .background(KlinoteColor.document)
    }

    private var title: String {
        switch pending.kind {
        case .copy: "Not ready to copy"
        case .print: "Not ready to print"
        case .review: "Not ready to mark reviewed"
        }
    }

    private struct Jump: Identifiable {
        enum Target { case sentence(String), section(String) }
        let id: String
        let label: String
        let symbol: String
        let target: Target
    }

    private var jumps: [Jump] {
        var result: [Jump] = []
        if let id = unverifiedSentenceID {
            result.append(Jump(
                id: "source", label: "Show the sentence to check", symbol: "text.magnifyingglass",
                target: .sentence(id)
            ))
        }
        if let section = missingSection {
            result.append(Jump(
                id: "section", label: "Write the \(section.title) section", symbol: "square.and.pencil",
                target: .section(section.key)
            ))
        }
        if encounter.transcript?.nameChecks?.isEmpty == false {
            result.append(Jump(
                id: "names", label: "Check the names", symbol: "person.crop.circle.badge.questionmark",
                target: .sentence(encounter.note?.sections.flatMap(\.sentences).first?.id ?? "")
            ))
        }
        return result
    }

    private func perform(_ jump: Jump) {
        switch jump.target {
        case .sentence(let id):
            model.selectedSentenceID = id.isEmpty ? nil : id
        case .section(let key):
            model.focusMissingSection(key)
        }
    }
}

private struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(KlinoteColor.hairline)
            .frame(height: 1)
    }
}
