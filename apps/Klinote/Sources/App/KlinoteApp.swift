//
// KlinoteApp.swift
//
// Menu-bar first. Klinote has no Dock presence until a window is open, because
// the clinician's attention belongs to the patient, not to us.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct KlinoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Klinote — \(model.recordingState.word)")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            // Without this the app has no Edit menu at all, and the standard
            // paste shortcut does nothing — including in the paste-transcript
            // sheet, which is the whole zero-download path.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { send(#selector(NSText.cut(_:))) }
                    .keyboardShortcut("x")
                Button("Copy") { send(#selector(NSText.copy(_:))) }
                    .keyboardShortcut("c")
                Button("Paste") { send(#selector(NSText.paste(_:))) }
                    .keyboardShortcut("v")
                Divider()
                Button("Select All") { send(#selector(NSText.selectAll(_:))) }
                    .keyboardShortcut("a")
            }

            // The global hotkeys stay on Carbon so they work while the
            // clinician is in the record system. These menu items are for
            // discovery, so they deliberately bind no shortcut of their own.
            CommandGroup(replacing: .printItem) {
                Button("Print…") { model.printSelectedNote() }
                    .keyboardShortcut("p")
                    .disabled(model.selectedEncounter?.note == nil)
            }

            CommandMenu("Consult") {
                Button("Record this consult") { model.startRecording() }
                    .disabled(model.recordingState.isActive)
                Button("Pause or resume") { model.togglePause() }
                    .disabled(!model.recordingState.isActive)
                Button("Stop and write the note") { model.stopAndDraft() }
                    .disabled(!model.recordingState.isActive)
                Divider()
                Button("Copy note") { model.copySelectedNote() }
                    .disabled(model.selectedEncounter?.note == nil)
                Button("Print…") { model.printSelectedNote() }
                    .disabled(model.selectedEncounter?.note == nil)
                Button("Mark as reviewed") { model.fileSelectedNote() }
                    .disabled(model.selectedEncounter?.state == .approved)
                Divider()
                Button("Make a referral letter") { model.makeDocumentFromSelection("referral_letter") }
                Button("Make the patient's copy") { model.makeDocumentFromSelection("patient_summary") }
                Button("Swap clinician and patient") { model.swapSpeakersAndRedraft() }
                    .disabled(model.selectedEncounter?.isSyntheticDemo != false)
            }
        }

        Settings {
            SettingsRootView(model: model)
        }
    }

    /// Standard first-responder actions, so the Edit menu reaches whichever
    /// text field currently has focus.
    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            AppModel.shared.bootstrap()
            AppModel.shared.revealLetterIfFirstLaunch()
        }

        // ⌥⌘R — start or stop recording.
        HotKeyCenter.shared.register(
            .toggleRecording,
            keyCode: kVK_ANSI_R,
            modifiers: optionKey | cmdKey
        ) {
            Task { @MainActor in AppModel.shared.toggleRecording() }
        }

        // ⌥⌘P — pause or resume, recording only.
        HotKeyCenter.shared.register(
            .togglePause,
            keyCode: kVK_ANSI_P,
            modifiers: optionKey | cmdKey
        ) {
            Task { @MainActor in
                AppModel.shared.togglePause()
            }
        }

        // ⌘⇧N — open the review window.
        HotKeyCenter.shared.register(
            .openKlinote,
            keyCode: kVK_ANSI_N,
            modifiers: cmdKey | shiftKey
        ) {
            Task { @MainActor in ReviewWindowController.shared.show() }
        }

        // ⌘⇧C — copy the selected note as Markdown.
        HotKeyCenter.shared.register(
            .copyNote,
            keyCode: kVK_ANSI_C,
            modifiers: cmdKey | shiftKey
        ) {
            Task { @MainActor in AppModel.shared.copySelectedNote() }
        }

        // ⌥⌘S — swap clinician and patient, rebuild the note.
        HotKeyCenter.shared.register(
            .swapSpeakers,
            keyCode: kVK_ANSI_S,
            modifiers: optionKey | cmdKey
        ) {
            Task { @MainActor in AppModel.shared.swapSpeakersAndRedraft() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloader = ModelDownloader.shared

    private var recordingWord: String {
        if model.recordingState.isPaused { return "Paused — not recording" }
        if model.recordingState.isHolding { return "Held — not recording" }
        return "Recording"
    }

    var body: some View {
        if let error = model.lastError {
            Text(error)
            Divider()
        }

        if case .downloading(let fraction) = downloader.state {
            Text("Downloading listening \(Int(fraction * 100))%")
            Divider()
        } else if case .missing = downloader.state {
            Button("Download listening…") { downloader.start() }
            Divider()
        } else if case .failed = downloader.state {
            Button("Retry listening download") { downloader.start() }
            Divider()
        }

        if model.recordingState.isDrafting {
            Text("Writing the note")
        } else if model.recordingState.isActive {
            Text(recordingWord)
            Button("Stop and write the note") { model.stopAndDraft() }
            if model.recordingState.isHolding {
                Button("End hold") { model.endHold() }
            } else if model.recordingState.isPaused {
                Button("Resume") { model.resumeRecording() }
            } else {
                Button("Pause") { model.pauseRecording() }
                Button("Hold — do not record this part") { model.holdRecording() }
            }
        } else {
            Button("Record this consult") { model.startRecording() }
        }

        Divider()

        ForEach(model.encounters.prefix(5)) { encounter in
            Button {
                model.selection = encounter.id
                ReviewWindowController.shared.show()
            } label: {
                Text(encounter.menuTitle)
            }
        }

        if !model.encounters.isEmpty { Divider() }

        Button("Copy note") { model.copySelectedNote() }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selectedEncounter?.note == nil)

        Button("Swap clinician and patient") { model.swapSpeakersAndRedraft() }
            .keyboardShortcut("s", modifiers: [.option, .command])
            .disabled(model.selectedEncounter?.isSyntheticDemo != false)

        Button("Open Klinote") { ReviewWindowController.shared.show() }
            .keyboardShortcut("n", modifiers: [.command, .shift])

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Klinote") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
