//
// SetupSheet.swift
//
// First run. Two things have to happen before a clinician records a patient:
// they have to know what this does with the audio, and they have to accept
// that telling the patient is theirs to do. The product's entire claim is
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
                Text("Clinical notes that never leave the room.")
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
                    title: "Tell the patient",
                    detail: "A strip on screen says a recording is happening. Letting the patient know, and following your college's and your jurisdiction's rules on recording a consultation, is your responsibility — not this app's."
                )
                Point(
                    symbol: "waveform",
                    title: listeningReady ? "Listening is ready" : "Listening downloads once",
                    detail: listeningReady
                        ? "The 465 MB speech model is already on this Mac. You can record a consult straight away."
                        : "Speech recognition needs a 465 MB model. It downloads once and stays on this Mac. You can skip it and paste a transcript instead."
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
                Text("Klinote could not open its encrypted store. If macOS asked for your keychain password and you chose Deny, your existing consults cannot be read. Quit and reopen Klinote, then choose Allow.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
                Rule()
            }

            Toggle(isOn: $acknowledged) {
                Text("I will tell patients when I record, and I will follow the rules that apply where I practise.")
                    .font(KlinoteFont.ui())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space12) {
                Text(acknowledged
                     ? "Notes are kept until you delete them, or set a retention period in Settings → Privacy."
                     : "Tick the box above to continue.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(acknowledged ? KlinoteColor.tertiary : KlinoteColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !listeningReady {
                    Button("Paste a transcript instead") {
                        finish()
                        model.isPasting = true
                    }
                    .disabled(!acknowledged)
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(KlinotePrimaryButtonStyle())
                    .disabled(!acknowledged)
            }
        }
        .padding(KlinoteMetrics.sheetInset)
        .frame(width: KlinoteMetrics.sheetWidth)
        .background(KlinoteColor.document)
    }

    private var listeningReady: Bool { downloader.state == .ready }
    private var noteReady: Bool { downloader.noteState == .ready }

    /// There must always be an action here that finishes setup. The first
    /// version turned the primary button into a disabled *label* — "Listening
    /// is ready" — once the model was already on disk, which left a clinician
    /// who wanted to record with no way past this screen except the paste
    /// button, which is the wrong thing to press.
    /// One button for both models.
    ///
    /// "Which model do I want" is not a question to put to a clinician on first
    /// run. Both are needed before the first note is worth reading, and the
    /// second is the one people would have skipped — leaving them with the
    /// thinner draft and no way to know.
    private var primaryTitle: String {
        switch (downloader.state, noteReady) {
        case (.ready, true): "Start using Klinote"
        case (.ready, false): "Download Quire (1.9 GB)"
        case (.downloading(let fraction), _): "Continue · listening \(Int(fraction * 100))%"
        case (_, true): "Download listening (465 MB)"
        default: "Download both (2.3 GB)"
        }
    }

    private func primaryAction() {
        // startAll sequences them: listening first, Quire when it lands. They
        // cannot run at once — there is one task and one progress observation.
        downloader.startAll()
        finish()
    }

    /// The only place setup is ever completed, so the acknowledgement is
    /// always a deliberate click.
    private func finish() {
        model.didCompleteSetup = true
        model.isSettingUp = false
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
