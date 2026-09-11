//
// ReviewWindow.swift
//
// The signature surface: encounters as labelled spines, the note as a ruled
// letter, and the evidence in the margin.
//

import AppKit
import SwiftUI

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ReviewWindowController()

    private convenience init() {
        self.init(window: nil)
    }

    func show() {
        if let window {
            ActivationPolicy.enter()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nota"
        window.minSize = NSSize(width: 1040, height: 640)
        window.contentView = NSHostingView(rootView: ReviewWindow(model: AppModel.shared))
        window.setFrameAutosaveName("NotaReviewWindow")
        window.center()
        window.delegate = self
        self.window = window

        ActivationPolicy.enter()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.leave()
    }
}

struct ReviewWindow: View {
    @ObservedObject var model: AppModel
    @State private var showMargin = true

    var body: some View {
        NavigationSplitView {
            EncounterSidebar(model: model)
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: NotaMetrics.sidebarWidth,
                    max: 320
                )
        } detail: {
            DocumentView(model: model)
        }
        .inspector(isPresented: $showMargin) {
            MarginView(model: model)
                .inspectorColumnWidth(
                    min: 260,
                    ideal: NotaMetrics.marginColumnWidth,
                    max: 420
                )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: NotaMetrics.motionLayout)) {
                        showMargin.toggle()
                    }
                } label: {
                    Label("Evidence", systemImage: "sidebar.right")
                }
                .help("Show or hide the evidence margin")
            }
        }
        .environment(\.notaReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .frame(minWidth: 1040, minHeight: 640)
    }
}

// MARK: - Encounters

/// Ruled spines. Columns never move; only the state styling changes.
struct EncounterSidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TabLabel(text: "Encounters")
                Spacer()
                Button {
                    model.startRecording()
                } label: {
                    Image(systemName: "record.circle")
                }
                .buttonStyle(.borderless)
                .help("Record a consultation (⌥⌘R)")
            }
            .padding(.horizontal, NotaMetrics.space16)
            .padding(.vertical, NotaMetrics.space12)

            Hairline()

            if model.encounters.isEmpty {
                EmptyState(
                    title: "No encounters yet",
                    message: "Record a consultation, or open the bundled sample to see how a draft reads.",
                    action: (title: "Open the sample note", handler: { model.prepareDemoNote() })
                )
                .padding(NotaMetrics.space16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.encounters) { encounter in
                            EncounterSpine(
                                encounter: encounter,
                                isSelected: encounter.id == model.selection
                            )
                            .onTapGesture {
                                model.selection = encounter.id
                                model.selectedSentenceID = nil
                            }
                            Hairline()
                        }
                    }
                }
            }
        }
        .background(NotaColor.desk)
    }
}

struct EncounterSpine: View {
    let encounter: Encounter
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(encounter.patientRef)
                    .font(NotaFont.ui(13, weight: .medium))
                    .foregroundStyle(NotaColor.primary)
                Spacer(minLength: NotaMetrics.space8)
                Text(encounter.state.word)
                    .font(NotaFont.label())
                    .foregroundStyle(encounter.state.tone)
            }
            HStack(spacing: NotaMetrics.space8) {
                Text(Self.time(encounter.startedAt))
                    .font(NotaFont.data(10))
                    .foregroundStyle(NotaColor.secondary)
                Text(encounter.discipline.replacingOccurrences(of: "_", with: " "))
                    .font(NotaFont.label())
                    .foregroundStyle(NotaColor.tertiary)
                if encounter.isSyntheticDemo {
                    Text("sample")
                        .font(NotaFont.label())
                        .foregroundStyle(NotaColor.caution)
                }
            }
        }
        .padding(.horizontal, NotaMetrics.space16)
        .padding(.vertical, NotaMetrics.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? NotaColor.accent.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? NotaColor.accent : .clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
