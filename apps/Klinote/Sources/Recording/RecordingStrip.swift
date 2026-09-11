//
// RecordingStrip.swift
//
// The patient-visible indicator. This is the most consequential surface in the
// product: it carries the consent relationship, so it is deliberately plain,
// opaque, legible across a desk, and never hidden from screen capture.
//

import AppKit
import SwiftUI

@MainActor
final class RecordingStripController {
    static let shared = RecordingStripController()
    private var panel: NSPanel?

    func show(model: AppModel) {
        if let panel {
            reposition(panel)
            panel.orderFrontRegardless()
            return
        }

        let panel = StripPanel(
            contentRect: NSRect(x: 0, y: 0, width: 396, height: 148),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Visible on every Space and over full-screen apps, because the
        // consultation is not confined to one desktop.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingStripView(model: model))
        self.panel = panel
        reposition(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Top-right of whichever screen the pointer is on, inside the usable
    /// frame, and never under the notch.
    private func reposition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width - 16,
                y: visible.maxY - size.height - 16
            )
        )
    }
}

/// Never steals focus from the record system the clinician is working in.
final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RecordingStripView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isLive: Bool { model.recordingState.isRecording }
    private var isDrafting: Bool {
        if case .finalising = model.recordingState { return true }
        return false
    }

    private var headline: String {
        switch model.recordingState {
        case .paused: "Paused — not recording"
        case .holding: "Held — this part is not being recorded"
        case .finalising: "Writing the note on this Mac"
        default: "Recording this consult on this Mac only"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                RecordingLamp(
                    isRecording: isLive && !model.recordingState.isHolding,
                    isPaused: model.recordingState.isPaused || model.recordingState.isHolding
                )
                Text(headline)
                    .font(KlinoteFont.panelHeading())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: KlinoteMetrics.space8)
                Text(isDrafting ? "…" : Self.clock(model.elapsed))
                    .font(KlinoteFont.clock())
                    .monospacedDigit()
                    .foregroundStyle(KlinoteColor.secondary)
            }

            TraceView(
                level: model.traceLevel,
                isActive: isLive,
                samples: model.traceSamples,
                isPaused: model.recordingState.isPaused,
                reduceMotion: systemReduceMotion
            )
            .frame(height: 26)

            HStack(spacing: KlinoteMetrics.space8) {
                if model.recordingState.isHolding {
                    Button("End hold") { model.endHold() }
                        .controlSize(.small)
                        .disabled(isDrafting)
                        .accessibilityLabel("End the hold and start recording again")
                } else if model.recordingState.isPaused {
                    Button("Resume") { model.resumeRecording() }
                        .controlSize(.small)
                        .disabled(isDrafting)
                        .accessibilityLabel("Resume recording")
                } else {
                    Button("Pause") { model.pauseRecording() }
                        .controlSize(.small)
                        .disabled(isDrafting)
                        .accessibilityLabel("Pause recording")
                    // Not the same as pause: this part does not go in the note.
                    Button("Hold") { model.holdRecording() }
                        .controlSize(.small)
                        .disabled(isDrafting)
                        .help("Stop recording without ending the consult. The held part is not captured and the note says so.")
                        .accessibilityLabel("Hold: do not record this part")
                }

                Button("Stop and write the note") {
                    model.stopAndDraft()
                }
                .controlSize(.small)
                .disabled(isDrafting)
                .accessibilityLabel("Stop recording and write the note")

                Spacer(minLength: 0)

                Text("Audio stays on this Mac")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
            }
        }
        .padding(KlinoteMetrics.space16)
        .frame(width: 380)
        .klinoteGlass(cornerRadius: KlinoteMetrics.radiusDocument, tint: KlinoteColor.record.opacity(0.18), interactive: true)
        .overlay(
            RoundedRectangle(cornerRadius: KlinoteMetrics.radiusDocument, style: .continuous)
                .strokeBorder(KlinoteColor.record.opacity(0.65), lineWidth: 1.5)
        )
        .environment(\.klinoteReduceMotion, systemReduceMotion)
        .accessibilityElement(children: .contain)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
