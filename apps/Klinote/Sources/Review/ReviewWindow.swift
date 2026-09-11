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
        window.title = "Klinote"
        window.subtitle = "Clinical notes that never leave the room"
        window.minSize = NSSize(width: 1040, height: 640)
        window.contentView = NSHostingView(rootView: ReviewWindow(model: AppModel.shared))
        window.setFrameAutosaveName("KlinoteReviewWindow")
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
                .background(KlinoteColor.desk, ignoresSafeAreaEdges: .all)
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: KlinoteMetrics.sidebarWidth,
                    max: 320
                )
        } detail: {
            DocumentView(model: model)
        }
        .inspector(isPresented: $showMargin) {
            MarginView(model: model)
                .background(KlinoteColor.margin, ignoresSafeAreaEdges: .all)
                .inspectorColumnWidth(
                    min: 260,
                    ideal: KlinoteMetrics.marginColumnWidth,
                    max: 420
                )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.lastError {
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    Text(error)
                        .font(KlinoteFont.ui(12))
                        .foregroundStyle(KlinoteColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") { model.lastError = nil }
                        .controlSize(.small)
                }
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
                .background(KlinoteColor.caution.opacity(0.14))
                .overlay(alignment: .bottom) { Hairline() }
            } else if let banner = model.copyBanner {
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    Text(banner)
                        .font(KlinoteFont.ui(12, weight: .medium))
                        .foregroundStyle(KlinoteColor.ink)
                    Spacer(minLength: 0)
                    Button("Dismiss") { model.copyBanner = nil }
                        .controlSize(.small)
                }
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
                .background(KlinoteColor.ink.opacity(0.08))
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: KlinoteMetrics.motionLayout)) {
                        showMargin.toggle()
                    }
                } label: {
                    Label("Evidence", systemImage: "sidebar.right")
                }
                .help("Show or hide the evidence margin")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .help("Record this consult (⌥⌘R)")
                Button {
                    model.copySelectedNote()
                } label: {
                    Label(model.isCopying ? "Copied" : "Copy note", systemImage: model.isCopying ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.selectedEncounter?.note == nil)
                .help("Copy the note to paste into the record (⌘⇧C)")
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .environment(\.klinoteReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .background(KlinoteColor.desk)
        .frame(minWidth: 1040, minHeight: 640)
    }
}

// MARK: - Encounters

/// Ruled spines. Columns never move; only the state styling changes.
struct EncounterSidebar: View {
    @ObservedObject var model: AppModel
    @State private var renameID: String?
    @State private var renameDraft = ""
    @State private var pendingDelete: Encounter?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TabLabel(text: "Encounters")
                Spacer()
                Button {
                    model.startRecording()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Record this consult (⌥⌘R)")
            }
            .padding(.horizontal, KlinoteMetrics.space16)
            .padding(.vertical, KlinoteMetrics.space12)

            Hairline()

            if model.encounters.isEmpty {
                EmptyState(
                    title: "No consults yet",
                    message: "Record a consult, or open the sample to see how a note reads.",
                    action: (title: "Open the sample note", handler: { model.prepareDemoNote() })
                )
                .padding(KlinoteMetrics.space16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.encounters) { encounter in
                            EncounterSpine(
                                encounter: encounter,
                                isSelected: encounter.id == model.selection,
                                onRename: {
                                    renameDraft = encounter.patientRef
                                    renameID = encounter.id
                                },
                                onCopy: {
                                    model.selection = encounter.id
                                    model.copySelectedNote()
                                },
                                onDelete: { pendingDelete = encounter }
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

            Hairline()
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(KlinoteColor.secondary)
                Spacer()
            }
            .padding(.horizontal, KlinoteMetrics.space16)
            .padding(.vertical, KlinoteMetrics.space12)
        }
        .background(KlinoteColor.desk)
        .alert("Rename consult", isPresented: Binding(
            get: { renameID != nil },
            set: { if !$0 { renameID = nil } }
        )) {
            TextField("Code", text: $renameDraft)
            Button("Save") {
                if let id = renameID { model.renameEncounter(id, to: renameDraft) }
                renameID = nil
            }
            Button("Cancel", role: .cancel) { renameID = nil }
        } message: {
            Text("This is the consult code on this Mac, not a name in the record.")
        }
        .confirmationDialog(
            "Delete this consult?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete?.id { model.deleteEncounter(id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removed from this Mac. Not removed from your record system.")
        }
    }
}

struct EncounterSpine: View {
    let encounter: Encounter
    let isSelected: Bool
    var onRename: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(encounter.isSyntheticDemo ? "Sample" : Self.time(encounter.startedAt))
                    .font(KlinoteFont.data(12))
                    .foregroundStyle(KlinoteColor.primary)
                Spacer(minLength: KlinoteMetrics.space8)
                Text(encounter.state.word)
                    .font(KlinoteFont.label())
                    .foregroundStyle(encounter.state.tone)
                Menu {
                    Button("Rename…", action: onRename)
                    Button("Copy note", action: onCopy)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KlinoteColor.secondary)
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .opacity(isSelected || hovering ? 1 : 0)
                .help("Consult actions")
            }
            HStack(spacing: KlinoteMetrics.space8) {
                Text(encounter.patientRef)
                    .font(KlinoteFont.data(11))
                    .foregroundStyle(KlinoteColor.secondary)
                    .lineLimit(1)
                Text(encounter.templateId)
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
            }
        }
        .padding(.horizontal, KlinoteMetrics.space16)
        .padding(.vertical, KlinoteMetrics.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? KlinoteColor.accent.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? KlinoteColor.accent : .clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Copy note", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
