//
// SetupSheet.swift
//
// First run. Two things have to happen before a therapist records a session:
// they have to know what this does with the audio, and they have to accept
// that telling the client is theirs to do. The product's entire claim is
// privacy, so this is the one screen that must not be skipped.
//
// It is not a wall. The download is offered as a choice, and the paste path
// works with nothing downloaded at all.
//

import SwiftUI

struct SetupSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloader = ModelDownloader.shared
    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space24) {
            VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
                BrandMark(size: 20)
                Text("The session stays in the room. The note still gets written.")
                    .font(KlinoteFont.tagline())
                    .foregroundStyle(KlinoteColor.primary)
            }

            Rule()

            VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
                Point(
                    symbol: "lock",
                    title: "Nothing is sent anywhere",
                    detail: "Klinote has no server and no account. Audio is transcribed on this Mac, the note is written on this Mac, and the database is encrypted with a key in your Keychain."
                )
                Point(
                    symbol: "person.wave.2",
                    title: "Tell the client",
                    detail: "A strip on screen says a recording is happening. Letting the client know, and following your college's and your jurisdiction's rules on recording a session, is your responsibility — not this app's."
                )
                Point(
                    symbol: "waveform",
                    title: listeningReady ? "Listening is ready" : "Listening is not available",
                    detail: listeningReady
                        ? "Speech recognition is part of macOS, so there is nothing to download before your first session. You can record straight away."
                        : Transcriber.unavailableReason
                            ?? "This Mac cannot transcribe on device. You can still paste a transcript you already have."
                )
                Point(
                    symbol: "text.alignleft",
                    title: noteReady ? "Writing is ready" : "Writing the note takes a model too",
                    detail: noteReady
                        ? "Quire is on this Mac. It reads the transcript and writes the note."
                        : "Reading the words is not the same as writing the note. Quire does that — 1.9 GB, once, on this Mac. Without it the built-in rules write a thinner draft, and nothing on screen would tell you which you got. Add it now or later; if it arrives later it writes the note again from the saved words."
                )
            }

            Rule()

            if model.storeError != nil {
                Text("Klinote could not open its encrypted store. If macOS asked for your keychain password and you chose Deny, your existing sessions cannot be read. Quit and reopen Klinote, then choose Allow.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
                Rule()
            }

            Toggle(isOn: $acknowledged) {
                Text("I will tell clients when I record, and I will follow the rules that apply where I practise.")
                    .font(KlinoteFont.ui())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            if case .downloading(let fraction) = downloader.noteState {
                HStack(spacing: KlinoteMetrics.space8) {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 220)
                    Text("Writing model \(Int(fraction * 100))%")
                        .font(KlinoteFont.label())
                        .foregroundStyle(KlinoteColor.secondary)
                }
            } else if case .failed(let message) = downloader.noteState {
                Text("The writing model did not download: \(message) You can add it later — a note already written is written again from its saved transcript.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                Text(acknowledged
                     ? "Notes are kept until you delete them, or set a retention period in Settings → Privacy."
                     : "Tick the box above to continue.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(acknowledged ? KlinoteColor.tertiary : KlinoteColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Paste what was said") {
                    model.completeSetup()
                    model.beginTyping()
                }
                .disabled(!acknowledged)
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(KlinotePrimaryButtonStyle())
                    .disabled(!acknowledged)
            }
        }
        .padding(KlinoteMetrics.sheetInset)
        .frame(width: KlinoteMetrics.sheetWidth)
        .background(KlinoteColor.document)
    }

    /// Listening is a capability of the Mac now, not something this app has on
    /// disk. See `Transcriber`.
    private var listeningReady: Bool { Transcriber.isAvailable }
    private var noteReady: Bool { downloader.noteState == .ready }

    /// There must always be an action here that finishes setup. An earlier
    /// version turned the primary button into a disabled *label* — "Listening is
    /// ready" — once the model was already on disk, which left a clinician who
    /// wanted to record with no way past this screen except the paste button,
    /// which is the wrong thing to press.
    ///
    /// One download is left, so one button. It used to sequence two and label
    /// itself from both, which read "Download Quire (1.9 GB)" while that
    /// download was already running. Recording no longer depends on it at all —
    /// Quire is an upgrade to the draft, not a ticket to the microphone.
    private var primaryTitle: String {
        switch downloader.noteState {
        case .ready: "Start using Klinote"
        case .downloading(let fraction): "Continue · writing \(Int(fraction * 100))%"
        case .failed: "Try the writing download again"
        case .missing: "Download Quire (1.9 GB) and record"
        }
    }

    private func primaryAction() {
        downloader.startNote()
        model.completeSetupThenRecord()
    }
}

/// One claim, with a symbol so it can be skimmed rather than read.
private struct Point: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: KlinoteMetrics.space12) {
            Image(systemName: symbol)
                .font(.system(size: KlinoteMetrics.iconRegular, weight: .medium))
                .foregroundStyle(KlinoteColor.ink)
                .frame(width: 20, alignment: .center)
                .padding(.top, KlinoteMetrics.inline2)
            VStack(alignment: .leading, spacing: KlinoteMetrics.inline2) {
                Text(title)
                    .font(KlinoteFont.emphasis())
                    .foregroundStyle(KlinoteColor.primary)
                Text(detail)
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(KlinoteColor.hairline)
            .frame(height: 1)
    }
}
