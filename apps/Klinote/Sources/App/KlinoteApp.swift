//
// KlinoteApp.swift
//
// Menu-bar first. Klinote has no Dock presence until a window is open, because
// the therapist's attention belongs to the client, not to us.
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
                Button("Print…") { model.requestPrintFromSelection() }
                    .keyboardShortcut("p")
                    .disabled(model.selectedEncounter?.note == nil)
            }

            CommandMenu("Session") {
                Button("Record this session") { model.startRecording() }
                    .disabled(model.recordingState.isActive)
                Button("Paste what was said") { model.beginTyping() }
                    .disabled(model.recordingState.isActive)
                Button("Pause or resume") { model.togglePause() }
                    .disabled(!model.recordingState.isActive)
                Button("Stop and write the note") { model.stopAndDraft() }
                    .disabled(!model.recordingState.isActive)
                Divider()
                Button("Copy note") { model.copySelectedNote() }
                    .disabled(model.selectedEncounter?.note == nil)
                Button("Correct the selected sentence…") {
                    if let id = model.selectedSentenceID { model.editingSentenceID = id }
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selectedSentenceID == nil || model.editingSentenceID != nil)
                Button("Print…") { model.requestPrintFromSelection() }
                    .disabled(model.selectedEncounter?.note == nil)
                Button("Mark as reviewed") { model.fileSelectedNote() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.selectedEncounter?.state == .approved)
                Divider()
                Button("Make a referral letter") { model.makeDocumentFromSelection("referral_letter") }
                Button("Make the client's copy") { model.makeDocumentFromSelection("patient_summary") }
                Button("Swap therapist and client") { model.swapSpeakersAndRedraft() }
                    .disabled(model.selectedEncounter?.isSyntheticDemo != false)
                Divider()
                Button("Undo last note edit") { model.undoLastEdit() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.selectedEncounter == nil)
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
    /// Clicking the app again, or `open -a Klinote`, should produce the
    /// window rather than nothing.
    func applicationShouldHandleReopen(
        _ application: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows {
            ReviewWindowController.shared.show()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Decide the activation policy once, here.
        //
        // This used to start as .accessory and flip to .regular when the window
        // appeared. Becoming accessory at launch hands focus back to whatever
        // was frontmost, and asking for it again a moment later does not get it
        // back reliably — the window opened behind the app the clinician came
        // from, which looks exactly like "no window opened".
        let model = AppModel.shared
        NSApp.setActivationPolicy(model.opensWindowAtLaunch ? .regular : .accessory)

        Task { @MainActor in
            model.bootstrap()
            // One runloop turn, so the window is created after launch has
            // settled. Activating too early in launch is ignored.
            try? await Task.sleep(for: .milliseconds(50))
            model.openWindowIfNeeded()
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

        // ⌥⌘S — swap therapist and client, rebuild the note.
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

    /// Quitting discards the in-memory copy — which, after a save failure, is
    /// the *only* copy. A silent quit here would destroy exactly the work the
    /// save status just told the clinician was at risk, so the app asks, and
    /// the retry it offers is the same one the desk offers.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A live recording is work that exists nowhere else. Quitting used to
        // ask only about unsaved notes, so ⌘Q during a session discarded the
        // recording and left its plaintext temp file behind.
        let state = MainActor.assumeIsolated { AppModel.shared.recordingState }
        if state.isActive || state.isDrafting {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = state.isDrafting
                ? "A note is still being written"
                : "A session is still recording"
            alert.informativeText = state.isDrafting
                ? "Quitting now discards the note being written. Let it finish, or quit and lose this draft."
                : "Quitting now discards the recording and the words not yet written. Stop the recording and let the note finish first, or quit and lose this part of the session."
            alert.addButton(withTitle: state.isDrafting ? "Keep working" : "Stop recording and stay open")
            alert.addButton(withTitle: "Quit anyway")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if !state.isDrafting {
                    MainActor.assumeIsolated { AppModel.shared.stopAndDraft() }
                }
                return .terminateCancel
            case .alertSecondButtonReturn:
                MainActor.assumeIsolated {
                    Recorder.shared.stop()
                    Recorder.shared.cleanup()
                }
                return .terminateNow
            default:
                return .terminateCancel
            }
        }

        let unsaved = MainActor.assumeIsolated { () -> [String] in
            AppModel.shared.unsavedEncounterIDs.sorted()
        }
        guard !unsaved.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = unsaved.count == 1
            ? "1 session has not been saved"
            : "\(unsaved.count) sessions have not been saved"
        alert.informativeText = "Quitting now loses the changes on screen. The encrypted store refused the last save, so this Mac holds no copy of them."
        alert.addButton(withTitle: "Retry saving")
        alert.addButton(withTitle: "Quit anyway")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let stillUnsaved = MainActor.assumeIsolated { () -> Set<String> in
                let model = AppModel.shared
                for id in unsaved { model.retrySave(of: id) }
                return model.unsavedEncounterIDs
            }
            // The retry either made the disk true or it did not. Quitting on
            // a failed retry would be the same destruction with one extra
            // step; staying open keeps the work alive and the banner honest.
            return stillUnsaved.isEmpty ? .terminateNow : .terminateCancel
        }
        return response == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
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

        // The only download left is the note model. Listening used to appear
        // here too — 465 MB before the app could transcribe anything — and that
        // is gone with whisper.cpp.
        if case .downloading(let fraction) = downloader.noteState {
            Text("Downloading the note model \(Int(fraction * 100))%")
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
            Button("Record this session") { model.startRecording() }
            Button("Paste what was said") { model.beginTyping() }
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

        Button("Swap therapist and client") { model.swapSpeakersAndRedraft() }
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
