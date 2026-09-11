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

    /// SwiftUI opens the Settings scene by itself when the app launches as a
    /// regular app — a menu-bar app with a `Settings` scene has no other
    /// "main" window to put on screen. Nobody asked for Settings, and it lands
    /// on top of the letter and the first-run sheet.
    ///
    /// Matched on the frame autosave name, which is the identifier macOS and
    /// SwiftUI both use for that window, rather than on a title we would be
    /// guessing at.
    func closeStraySettingsWindow() {
        for window in NSApp.windows
        where window.frameAutosaveName == "com_apple_SwiftUI_Settings_window" {
            window.close()
        }
    }

    /// Whether the letter is actually on screen. The copy guard needs to know
    /// whether the clinician can see which consult they are copying.
    var isShowing: Bool {
        window?.isVisible == true && window?.isMiniaturized == false
    }

    func show() {
        if let window {
            ActivationPolicy.becomeRegular()
            window.makeKeyAndOrderFront(nil)
            ActivationPolicy.activate()
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

        // Policy first, then the window, then activate. Activating before the
        // window is on screen is dropped by the window server, which leaves a
        // visible window with no menu bar and the focus still in whatever app
        // the clinician came from.
        ActivationPolicy.becomeRegular()
        window.makeKeyAndOrderFront(nil)
        ActivationPolicy.activate()
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
            if let storeError = model.storeError {
                // A denied Keychain key would otherwise look like lost history.
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    Text("Klinote could not open its encrypted store: \(storeError)")
                        .font(KlinoteFont.ui(12))
                        .foregroundStyle(KlinoteColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") { model.storeError = nil }
                        .controlSize(.small)
                }
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
                .background(KlinoteColor.caution.opacity(0.14))
                .overlay(alignment: .bottom) { Hairline() }
            } else if let error = model.lastError {
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
    @State private var search = ""
    @State private var renameID: String?
    @State private var renameDraft = ""
    @State private var pendingDelete: Encounter?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TabLabel(text: "Encounters")
                Spacer()
                Button {
                    model.isPasting = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Paste a transcript you already have")
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

            if !model.encounters.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KlinoteColor.tertiary)
                    TextField("Search consults", text: $search)
                        .textFieldStyle(.plain)
                        .font(KlinoteFont.ui(12))
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(KlinoteColor.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear the search")
                    }
                }
                .padding(.horizontal, KlinoteMetrics.space12)
                .padding(.vertical, 6)
                .background(KlinoteColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                .padding(.horizontal, KlinoteMetrics.space12)
                .padding(.bottom, KlinoteMetrics.space8)
            }

            Hairline()

            if model.encounters.isEmpty {
                VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
                    Text("No consults yet")
                        .font(KlinoteFont.ui(15, weight: .semibold))
                        .foregroundStyle(KlinoteColor.primary)
                    Text("Already have a transcript? Paste it and get a note now — no download. Or record a consult.")
                        .font(KlinoteFont.ui())
                        .foregroundStyle(KlinoteColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Paste a transcript") { model.isPasting = true }
                        .buttonStyle(KlinotePrimaryButtonStyle())
                    Button("Open the sample note") { model.prepareDemoNote() }
                        .buttonStyle(.plain)
                        .font(KlinoteFont.ui())
                        .foregroundStyle(KlinoteColor.ink)
                }
                .padding(KlinoteMetrics.space16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.encounterGroups(matching: search), id: \.day) { group in
                            Section {
                                ForEach(group.encounters) { encounter in
                            EncounterSpine(
                                encounter: encounter,
                                isSelected: encounter.id == model.selection,
                                displayName: model.displayName(for: encounter),
                                documents: model.documentTemplates,
                                onRename: {
                                    renameDraft = encounter.patientRef
                                    renameID = encounter.id
                                },
                                onCopy: {
                                    model.requestCopy(of: encounter.id)
                                },
                                onMakeDocument: { templateId in
                                    model.makeDocument(from: encounter.id, templateId: templateId)
                                },
                                onDelete: { pendingDelete = encounter }
                            )
                            .onTapGesture {
                                model.selection = encounter.id
                                model.selectedSentenceID = nil
                            }
                            Hairline()
                                }
                            } header: {
                                HStack {
                                    TabLabel(text: group.day)
                                    Spacer()
                                    Text("\(group.encounters.count)")
                                        .font(KlinoteFont.data(10))
                                        .foregroundStyle(KlinoteColor.tertiary)
                                }
                                .padding(.horizontal, KlinoteMetrics.space16)
                                .padding(.vertical, 6)
                                .background(KlinoteColor.margin)
                                .overlay(alignment: .top) { Hairline() }
                                .overlay(alignment: .bottom) { Hairline() }
                            }
                        }
                    }
                }
            }

            if model.encounters.isEmpty == false,
               model.encounterGroups(matching: search).isEmpty {
                EmptyState(
                    title: "Nothing matched",
                    message: "No consult matches \"\(search)\"."
                )
                .padding(KlinoteMetrics.space16)
                Spacer()
            }

            if !model.openTaskRows.isEmpty {
                Hairline()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.openTaskRows, id: \.task.id) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Button {
                                    model.setTask(row.task, done: true)
                                } label: {
                                    Image(systemName: "square")
                                        .font(.system(size: 11))
                                        .foregroundStyle(KlinoteColor.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .help("Tick when you have done this.")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.task.text)
                                        .font(KlinoteFont.ui(11.5))
                                        .foregroundStyle(KlinoteColor.primary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(
                                        "\(row.encounter.patientRef) · "
                                            + EncounterSpine.time(row.encounter.startedAt)
                                    )
                                    .font(KlinoteFont.data(10))
                                    .foregroundStyle(KlinoteColor.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = row.encounter.id
                                model.selectedSentenceID = nil
                                ReviewWindowController.shared.show()
                            }
                            Hairline()
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        TabLabel(text: "Still to do")
                        Spacer()
                        Text("\(model.openTaskRows.count)")
                            .font(KlinoteFont.data(10))
                            .foregroundStyle(KlinoteColor.ink)
                    }
                }
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
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
        .sheet(isPresented: $model.isPasting) {
            PasteTranscriptSheet(model: model)
        }
        .sheet(item: $model.pendingCopy) { encounter in
            CopyConfirmSheet(encounter: encounter, model: model)
        }
        .sheet(isPresented: $model.isSettingUp) {
            SetupSheet(model: model)
                .interactiveDismissDisabled()
        }
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
    var displayName: String = ""
    var documents: [TemplateSummary] = []
    var onRename: () -> Void = {}
    var onCopy: () -> Void = {}
    var onMakeDocument: (String) -> Void = { _ in }
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
                    if !documents.isEmpty {
                        Menu("Make a document") {
                            ForEach(documents) { template in
                                Button(template.name) { onMakeDocument(template.id) }
                            }
                        }
                        Divider()
                    }
                    Button("Rename…", action: onRename)
                    Button("Copy", action: onCopy)
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
                Text(displayName.isEmpty ? encounter.templateId : displayName)
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
                    .lineLimit(1)
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
            if !documents.isEmpty {
                Menu("Make a document") {
                    ForEach(documents) { template in
                        Button(template.name) { onMakeDocument(template.id) }
                    }
                }
                Divider()
            }
            Button("Rename…", action: onRename)
            Button("Copy", action: onCopy)
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
