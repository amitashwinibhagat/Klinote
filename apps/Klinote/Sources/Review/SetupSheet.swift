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
                Text("klinote")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(KlinoteColor.ink)
                Text("Clinical notes that never leave the room.")
                    .font(KlinoteFont.document(16, weight: .medium))
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
                    title: "Listening downloads once",
                    detail: "Speech recognition needs a 465 MB model. It downloads once and stays on this Mac. You can skip it and paste a transcript instead."
                )
            }

            Rule()

            Toggle(isOn: $acknowledged) {
                Text("I will tell patients when I record, and I will follow the rules that apply where I practise.")
                    .font(KlinoteFont.ui())
                    .foregroundStyle(KlinoteColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: KlinoteMetrics.space12) {
                Text("This build has no retention policy. Delete old consults in Settings.")
                    .font(KlinoteFont.label())
                    .foregroundStyle(KlinoteColor.tertiary)
                Spacer(minLength: 0)
                Button("Paste a transcript instead") {
                    finish()
                    model.isPasting = true
                }
                .disabled(!acknowledged)
                Button(downloadButtonTitle) {
                    downloader.start()
                    finish()
                }
                .buttonStyle(KlinotePrimaryButtonStyle())
                .disabled(!acknowledged || downloader.state == .ready)
            }
        }
        .padding(KlinoteMetrics.space32)
        .frame(width: 620)
        .background(KlinoteColor.document)
    }

    private var downloadButtonTitle: String {
        switch downloader.state {
        case .ready: "Listening is ready"
        case .downloading: "Downloading…"
        default: "Download listening (465 MB)"
        }
    }

    private func finish() {
        model.didCompleteSetup = true
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KlinoteColor.ink)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KlinoteFont.ui(13, weight: .semibold))
                    .foregroundStyle(KlinoteColor.primary)
                Text(detail)
                    .font(KlinoteFont.ui(12))
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
