//
// NotaApp.swift
//
// Menu-bar first. Nota has no Dock presence until a window is open, because
// the clinician's attention belongs to the patient, not to us.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct NotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Nota — \(model.recordingState.word)")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            AppModel.shared.bootstrap()
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
                let model = AppModel.shared
                guard model.recordingState.isActive else { return }
                if model.recordingState.isPaused {
                    model.resumeRecording()
                } else {
                    model.pauseRecording()
                }
            }
        }

        // ⌘⇧N — open the review window.
        HotKeyCenter.shared.register(
            .openNota,
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

    var body: some View {
        if let error = model.lastError {
            Text(error)
            Divider()
        }

        if case .downloading(let fraction) = downloader.state {
            Text("Downloading speech engine \(Int(fraction * 100))%")
            Divider()
        } else if case .missing = downloader.state {
            Button("Download speech engine…") { downloader.start() }
            Divider()
        } else if case .failed = downloader.state {
            Button("Retry speech engine download") { downloader.start() }
            Divider()
        }

        if model.recordingState.isDrafting {
            Text("Drafting the note on this Mac")
        } else if model.recordingState.isActive {
            Text(model.recordingState.isPaused ? "Paused — not recording" : "Recording")
            Button("Stop and draft") { model.stopAndDraft() }
            if model.recordingState.isPaused {
                Button("Resume") { model.resumeRecording() }
            } else {
                Button("Pause") { model.pauseRecording() }
            }
        } else {
            Button("Start recording") { model.startRecording() }
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

        Button("Open Nota") { ReviewWindowController.shared.show() }
            .keyboardShortcut("n", modifiers: [.command, .shift])

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Nota") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
