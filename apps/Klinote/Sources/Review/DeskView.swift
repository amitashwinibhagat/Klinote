//
// DeskView.swift
//
// S1 — home. A blank letter on the desk. The three paths are how ink gets
// onto it. Motion: 160 ms ink-rule on hover; 220 ms swap into the typer;
// the 420 ms Assemble lives on the workspace change in ReviewWindow.
//

import SwiftUI

struct DeskView: View {
    @ObservedObject var model: AppModel
    @Environment(\.klinoteReduceMotion) private var reduceMotion
    @State private var draft = ""

    var body: some View {
        ZStack {
            DeskBlotter()
            HStack {
                Spacer(minLength: 0)
                paper
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(KlinoteMetrics.space48)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KlinoteColor.desk)
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space24) {
            VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
                BrandMark(size: 20)
                Text("How is this session getting in?")
                    .font(KlinoteFont.documentTitle())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The next client is soon. Nothing leaves this Mac.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }

            LetterheadRule()

            Group {
                if model.isTyping {
                    typer
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                } else {
                    paths
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: KlinoteMetrics.motionState) : .easeInOut(duration: KlinoteMetrics.motionLayout),
                value: model.isTyping
            )

            if let waiting = model.uncopied.first {
                Hairline()
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
                        TabLabel(text: "Still on this Mac")
                        Text("\(EncounterSpine.time(waiting.startedAt)) · \(model.displayName(for: waiting))")
                            .font(KlinoteFont.ui())
                            .foregroundStyle(KlinoteColor.primary)
                    }
                    Spacer(minLength: 0)
                    Button("Copy it") {
                        model.openLetter(waiting.id)
                        model.copySelectedNote()
                    }
                    .buttonStyle(KlinotePrimaryButtonStyle())
                }
            }

            HStack(spacing: KlinoteMetrics.space16) {
                Button("Earlier") { model.showEarlier() }
                    .buttonStyle(.plain)
                    .font(KlinoteFont.ui())
                    .foregroundStyle(KlinoteColor.ink)
                SettingsLink {
                    Text("Settings")
                        .font(KlinoteFont.ui())
                        .foregroundStyle(KlinoteColor.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(KlinoteMetrics.space32)
        .background(KlinoteColor.document)
        .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous)
                .strokeBorder(KlinoteColor.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var paths: some View {
        VStack(alignment: .leading, spacing: 0) {
            PathRow(
                mark: .dictate,
                title: "Dictate the note",
                detail: "You talk. The room is empty. Audio stays on this Mac."
            ) {
                model.startDictating()
            }
            Hairline()
            PathRow(
                mark: .type,
                title: "Type or paste",
                detail: "The words, on this page. No download."
            ) {
                model.beginTyping()
            }
            Hairline()
            PathRow(
                mark: .record,
                title: "Record the session",
                detail: "The client can see the lamp."
            ) {
                model.startRecording(kind: .session)
            }
        }
        .disabled(model.recordingState.isActive)
    }

    private var typer: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            Text("What was said, or what you need in the note.")
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
            TextEditor(text: $draft)
                .font(KlinoteFont.documentMinor())
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .padding(KlinoteMetrics.space8)
                .background(KlinoteColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous)
                        .strokeBorder(KlinoteColor.hairline, lineWidth: 1)
                )
            HStack {
                Button("Back") {
                    draft = ""
                    model.isTyping = false
                }
                .buttonStyle(.plain)
                .font(KlinoteFont.ui())
                .foregroundStyle(KlinoteColor.secondary)
                Spacer()
                Button("Make the note") {
                    model.makeNote(fromPastedText: draft)
                }
                .buttonStyle(KlinotePrimaryButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - Ruled path

/// A field on the blank letter. Hover draws the 2 pt ink rule that selection
/// uses on the filled letter — same mark, same meaning.
private struct PathRow: View {
    enum Mark { case dictate, type, record }

    let mark: Mark
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.klinoteReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: KlinoteMetrics.space12) {
                PathMark(kind: mark)
                    .frame(width: 28, height: 22)
                    .padding(.top, KlinoteMetrics.inline2)
                VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
                    Text(title)
                        .font(KlinoteFont.emphasis())
                        .foregroundStyle(KlinoteColor.ink)
                    Text(detail)
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, KlinoteMetrics.space12)
            .padding(.leading, KlinoteMetrics.space8)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(KlinoteColor.ink)
                    .frame(width: hovering ? KlinoteMetrics.ruleWidth : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: KlinoteMetrics.motionState),
            value: hovering
        )
    }
}

/// Marks taken from the product, not from a generic icon set: the trace, the
/// writing line, the lamp.
private struct PathMark: View {
    let kind: PathRow.Mark

    var body: some View {
        switch kind {
        case .dictate:
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    let heights: [CGFloat] = [4, 8, 6, 12, 7, 10, 5, 8]
                    Rectangle()
                        .fill(KlinoteColor.ink.opacity(0.55))
                        .frame(width: 2, height: heights[i])
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .accessibilityHidden(true)
        case .type:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(KlinoteColor.hairline)
                        .frame(width: i == 2 ? 16 : 24, height: 1)
                }
            }
            .accessibilityHidden(true)
        case .record:
            RecordingLamp(isRecording: false, isPaused: false)
        }
    }
}

/// Faint field rules on the desk around the paper — the blotter, not a grid
/// costume. Three horizontal rules only, letter measure, very quiet.
private struct DeskBlotter: View {
    var body: some View {
        GeometryReader { geo in
            let y0 = geo.size.height * 0.22
            VStack(spacing: geo.size.height * 0.18) {
                blotterRule
                blotterRule
                blotterRule
            }
            .padding(.top, y0)
            .padding(.horizontal, KlinoteMetrics.space48)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var blotterRule: some View {
        Rectangle()
            .fill(KlinoteColor.hairline.opacity(0.45))
            .frame(height: 1)
    }
}
