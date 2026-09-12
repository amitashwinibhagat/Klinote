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

    /// Order the letter front and take focus, asking more than once.
    ///
    /// A window ordered front before the activation policy has settled can be
    /// left created-but-not-shown: correct size, correct position, invisible.
    /// The window server reports it in the list and never on screen. One
    /// `makeKeyAndOrderFront` is not enough on a cold launch, so keep asking
    /// until it is visible, then stop.
    private func surface() {
        guard let window else { return }
        ActivationPolicy.becomeRegular()
        window.makeKeyAndOrderFront(nil)
        ActivationPolicy.activate()
        retrySurface(attempts: 10)
    }

    private func retrySurface(attempts: Int) {
        guard attempts > 0, let window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, let window = self.window else { return }
            guard !window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            ActivationPolicy.activate()
            self.retrySurface(attempts: attempts - 1)
        }
    }

    func show() {
        if window != nil {
            surface()
            return
        }

        // Sized for the shape the product actually has. The three columns need
        // sidebar 260 + document 624 + inspector 320 = 1204, plus dividers and
        // window chrome. The old 1280 default already squeezed the inspector to
        // about 160 pt against its own 260 minimum, clipping the evidence
        // column — the one part of this product nobody else has. The old 1040
        // minimum made a lie of the layout.
        // Clamp to the screen. A 13-inch MacBook is 1280 points wide, and an
        // ideal width larger than the display puts the sidebar off the left
        // edge — which is how a fixed 1400 managed to hide the consult list.
        let visible = NSScreen.main?.visibleFrame.size
            ?? NSSize(width: KlinoteMetrics.windowIdealWidth, height: KlinoteMetrics.windowIdealHeight)
        let margin = KlinoteMetrics.windowScreenMargin
        let width = min(KlinoteMetrics.windowIdealWidth, max(visible.width - margin * 2, 900))
        let height = min(KlinoteMetrics.windowIdealHeight, max(visible.height - margin * 2, 620))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Klinote"
        window.subtitle = "The session stays in the room"
        window.minSize = NSSize(
            width: min(KlinoteMetrics.windowMinWidth, visible.width),
            height: min(KlinoteMetrics.windowMinHeight, visible.height)
        )
        window.contentView = NSHostingView(rootView: ReviewWindow(model: AppModel.shared))
        window.setFrameAutosaveName("KlinoteReviewWindow")
        window.center()
        window.delegate = self
        self.window = window

        surface()
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.leave()
    }
}

struct ReviewWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // The banner sits above the split view in a VStack rather than in a
        // `safeAreaInset`. On macOS the sidebar column ignores that inset, so
        // the banner was drawn over the Encounters header and swallowed clicks
        // meant for the paste and record buttons there. It was not limited to
        // a store that failed to open: the copy receipt shows often enough to
        // block those buttons in ordinary use.
        VStack(spacing: 0) {
            banner
                .animation(.easeOut(duration: KlinoteMetrics.motionState), value: model.copyBanner)
            workspaceBody
                .id(model.workspace)
                .transition(workspaceTransition)
        }
        .animation(workspaceAnimation, value: model.workspace)
        .toolbar { workspaceToolbar }
        .sheet(isPresented: $model.isSettingUp) {
            SetupSheet(model: model)
                .interactiveDismissDisabled()
        }
        .sheet(item: $model.pendingCopy) { encounter in
            CopyConfirmSheet(encounter: encounter, model: model)
        }
        .sheet(item: $model.pendingPrint) { encounter in
            CopyConfirmSheet(encounter: encounter, model: model, isPrinting: true)
        }
        .environment(\.klinoteReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        .background(KlinoteColor.desk)
        .frame(
            minWidth: model.workspace == .letter || model.workspace == .sample ? 1040 : 640,
            minHeight: 640
        )
    }

    @ViewBuilder
    private var workspaceBody: some View {
        switch model.workspace {
        case .desk:
            DeskView(model: model)
        case .earlier:
            EncounterSidebar(model: model)
                .background(KlinoteColor.desk, ignoresSafeAreaEdges: .all)
        case .sample, .letter:
            letterPane
        }
    }

    /// Assemble: the letter settles onto the desk. Reduce Motion keeps the
    /// swap, drops the travel.
    private var workspaceAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: KlinoteMetrics.motionState)
            : .easeOut(duration: KlinoteMetrics.motionAssemble)
    }

    private var workspaceTransition: AnyTransition {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity
        )
    }

    /// The letter and the words. No caseload. Margin cannot hide: that column
    /// is the job "I did not say that."
    private var letterPane: some View {
        HStack(spacing: 0) {
            DocumentView(model: model)
            Rectangle()
                .fill(KlinoteColor.hairline)
                .frame(width: 1)
            MarginView(model: model)
                .frame(minWidth: 300, idealWidth: KlinoteMetrics.marginColumnWidth, maxWidth: 420)
                .background(KlinoteColor.margin, ignoresSafeAreaEdges: .all)
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if model.workspace == .letter || model.workspace == .sample {
                Button("Desk") { model.showDesk() }
            }
            if model.workspace == .earlier {
                Button("Desk") { model.showDesk() }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.workspace == .letter || model.workspace == .sample {
                Button {
                    model.copySelectedNote()
                } label: {
                    Label(model.isCopying ? "Copied" : "Copy note", systemImage: model.isCopying ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.selectedEncounter?.note == nil)
                .help("Copy the note to paste into the record (⌘⇧C)")
            }
            if model.workspace == .desk {
                Button("Earlier") { model.showEarlier() }
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")
        }
    }

    /// What the window can say above the columns. At most one shows.
    @ViewBuilder
    private var banner: some View {
        Group {
            if let storeError = model.storeError {
                // A denied Keychain key would otherwise look like lost history.
                HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                    Text("Klinote could not open its encrypted store: \(storeError)")
                        .font(KlinoteFont.caption())
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
                        .font(KlinoteFont.caption())
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
                        .font(KlinoteFont.caption(.medium))
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
                TabLabel(text: "Sessions")
                Spacer()
                Button {
                    model.isPasting = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Paste what was said")
                Button {
                    model.startRecording()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Record this session (⌥⌘R)")
            }
            .padding(.horizontal, KlinoteMetrics.space16)
            .padding(.vertical, KlinoteMetrics.space12)

            if !model.encounters.isEmpty {
                HStack(spacing: KlinoteMetrics.inline6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: KlinoteMetrics.iconSmall, weight: .medium))
                        .foregroundStyle(KlinoteColor.tertiary)
                    TextField("Search sessions", text: $search)
                        .textFieldStyle(.plain)
                        .font(KlinoteFont.caption())
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: KlinoteMetrics.iconSmall))
                                .foregroundStyle(KlinoteColor.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear the search")
                    }
                }
                .padding(.horizontal, KlinoteMetrics.space12)
                .padding(.vertical, KlinoteMetrics.inline6)
                .background(KlinoteColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous))
                .padding(.horizontal, KlinoteMetrics.space12)
                .padding(.bottom, KlinoteMetrics.space8)
            }

            Hairline()

            if model.encounters.isEmpty {
                VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
                    Text("No sessions yet")
                        .font(KlinoteFont.panelHeading())
                        .foregroundStyle(KlinoteColor.primary)
                    Text("Paste what was said and get a note now — no download. Or record the next session.")
                        .font(KlinoteFont.ui())
                        .foregroundStyle(KlinoteColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Paste what was said") { model.isPasting = true }
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
                                model.openLetter(encounter.id)
                            }
                            Hairline()
                                }
                            } header: {
                                HStack {
                                    TabLabel(text: group.day)
                                    Spacer()
                                    Text("\(group.encounters.count)")
                                        .font(KlinoteFont.microData())
                                        .foregroundStyle(KlinoteColor.tertiary)
                                }
                                .padding(.horizontal, KlinoteMetrics.space16)
                                .padding(.vertical, KlinoteMetrics.inline6)
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
                    message: "No session matches \"\(search)\"."
                )
                .padding(KlinoteMetrics.space16)
                Spacer()
            }

            Hairline()
            DisclosureGroup {
                if model.board.openRows.isEmpty {
                    Text("Nothing outstanding. Plan sentences from a note are listed here.")
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, KlinoteMetrics.space4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.board.openRows, id: \.task.id) { row in
                            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.inline6) {
                                Button {
                                    model.setTask(row.task, done: true)
                                } label: {
                                    Image(systemName: "square")
                                        .font(.system(size: KlinoteMetrics.iconSmall))
                                        .foregroundStyle(KlinoteColor.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .help("Tick when you have done this.")
                                VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
                                    Text(row.task.text)
                                        .font(KlinoteFont.caption())
                                        .foregroundStyle(KlinoteColor.primary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(
                                        "\(row.encounter.patientRef) · "
                                            + EncounterSpine.time(row.encounter.startedAt)
                                    )
                                    .font(KlinoteFont.microData())
                                    .foregroundStyle(KlinoteColor.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, KlinoteMetrics.space4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = row.encounter.id
                                model.selectedSentenceID = nil
                                ReviewWindowController.shared.show()
                            }
                            Hairline()
                        }
                    }
                    .padding(.top, KlinoteMetrics.space4)
                }
            } label: {
                    HStack {
                        TabLabel(text: "Still to do")
                        Spacer()
                        Text("\(model.board.openRows.count)")
                            .font(KlinoteFont.microData())
                            .foregroundStyle(KlinoteColor.ink)
                    }
                }
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)

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
        .alert("Rename session", isPresented: Binding(
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
            Text("This is the session code on this Mac, not a name in the record.")
        }
        .confirmationDialog(
            "Delete this session?",
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
        VStack(alignment: .leading, spacing: KlinoteMetrics.space4) {
            HStack(alignment: .firstTextBaseline) {
                Text(encounter.isSyntheticDemo ? "Sample" : Self.time(encounter.startedAt))
                    .font(KlinoteFont.clock())
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
                        .font(.system(size: KlinoteMetrics.iconSmall, weight: .semibold))
                        .foregroundStyle(KlinoteColor.secondary)
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .opacity(isSelected || hovering ? 1 : 0)
                .help("Session actions")
            }
            HStack(spacing: KlinoteMetrics.space8) {
                Text(encounter.patientRef)
                    .font(KlinoteFont.data())
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
                .frame(width: KlinoteMetrics.ruleWidth)
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

    /// One formatter for every row in the list. This was constructed inside
    /// the function, so it was allocated once per encounter per render.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
