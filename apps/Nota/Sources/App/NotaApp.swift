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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.recordingState.isActive {
            Text(model.recordingState.isPaused ? "Recording paused" : "Recording")
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
                Text("\(encounter.patientRef) · \(encounter.state.word)")
            }
        }

        if !model.encounters.isEmpty { Divider() }

        Button("Open Nota") { ReviewWindowController.shared.show() }
            .keyboardShortcut("n", modifiers: [.command, .shift])

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Nota") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
