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

    static func enter() {
        depth += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        depth = max(0, depth - 1)
        guard depth == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
