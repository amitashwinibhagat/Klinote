//
// HotKeys.swift
//
// System-wide shortcuts. Carbon is the only API that registers a hotkey which
// fires while another application is frontmost — which is the whole point:
// the clinician is looking at the record system, not at Klinote.
//

import AppKit
import Carbon.HIToolbox

/// `KLNT` as an OSType signature.
private let klinoteSignature: OSType = 0x4B4C4E54

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum ID: UInt32 {
        case toggleRecording = 1
        case togglePause = 2
        case openKlinote = 3
        case copyNote = 4
        case swapSpeakers = 5
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // A C function pointer cannot capture, so this reaches for the shared
        // instance instead of an enclosing scope.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    HotKeyCenter.shared.fire(id)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    func register(_ id: ID, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        handlers[id.rawValue] = action
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: klinoteSignature, id: id.rawValue)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            references.append(reference)
        } else {
            NSLog("Klinote: could not register hotkey \(id.rawValue) (status \(status))")
        }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }
}

// MARK: - Activation policy

/// A menu-bar app that occasionally shows a window needs to be `.regular`
/// while a window is open and `.accessory` otherwise. Reference counted so
/// several windows can be open at once.
@MainActor
enum ActivationPolicy {
    private static var depth = 0

    /// A menu-bar app is .accessory. With a window open it has to be a regular
    /// app, or the window has no menu bar and cannot take focus.
    static func becomeRegular() {
        // Idempotent: this is called on every show and every retry, and a
        // counter that grows with each one never returns to accessory.
        depth = max(depth, 1)
        NSApp.setActivationPolicy(.regular)
    }

    /// Bring the app forward. Call *after* the window is ordered front:
    /// activating earlier is dropped, and the window appears unfocused.
    ///
    /// The request is asynchronous and can be ignored while the activation
    /// policy is still changing from .accessory to .regular, so keep asking
    /// for a moment. Stop as soon as it takes, and stop anyway rather than
    /// fight the user for focus.
    static func activate() {
        bringForward()
        retry(attempts: 6)
    }

    private static func bringForward() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private static func retry(attempts: Int) {
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Activation is about the app, not the window. This used to
            // require a visible window before retrying, which meant that in
            // the one case that mattered — a window created but never ordered
            // on screen — it gave up immediately. Surfacing the window is
            // ReviewWindowController's job; see `surface()`.
            guard !NSRunningApplication.current.isActive else { return }
            bringForward()
            retry(attempts: attempts - 1)
        }
    }

    static func enter() {
        becomeRegular()
        activate()
    }

    static func leave() {
        depth = max(0, depth - 1)
        guard depth == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
