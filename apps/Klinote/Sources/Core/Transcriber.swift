//
// Transcriber.swift
//
// Speech to timed segments, on this Mac, with Apple's SpeechAnalyzer.
//
// This replaces whisper.cpp. The reasons are the product's own: there is no
// 465 MB model to download before a clinician can record anything, there is no
// large C++ model parser in the app bundle, and the recognition is the same one
// the OS uses everywhere else. What whisper.cpp gave us that this does not is
// speaker-boundary detection — SpeechTranscriber does not identify speakers — so
// `TurnTakingDiarizer` in the Rust core does that from the gaps between
// segments, and the margin still offers Swap.
//
// Recognition is deliberately the shell's job. `SpeechAnalyzer` is a Swift API
// and cannot be called from Rust, so the words cross the FFI to the pipeline,
// which owns diarisation, routing, grounding and completeness.
//

import AVFoundation
import CoreMedia
import Foundation
import Speech

/// One recognised span. Milliseconds from the start of the recording, because
/// that is the unit `AsrSegment` and the diariser work in.
struct RecognisedSegment {
    let startMs: UInt64
    let endMs: UInt64
    let text: String
    let confidence: Double?
}

enum TranscriberError: LocalizedError {
    case needsNewerMac
    case notInstalled
    case audioUnreadable(String)
    case nothingRecognised

    var errorDescription: String? {
        switch self {
        case .needsNewerMac:
            "Transcribing needs macOS 26 or later."
        case .notInstalled:
            "The on-device speech model is not available on this Mac."
        case .audioUnreadable(let detail):
            "The recording could not be read: \(detail)"
        case .nothingRecognised:
            "No speech was recognised in that recording."
        }
    }
}

enum Transcriber {
    /// Recorded on the transcript. A note that says how it was heard is a note
    /// a clinician can judge.
    static let engineName = "apple-speechanalyzer"

    /// The recognition locale. Klinote is English-only in the note templates,
    /// so this is stated rather than inferred from the system.
    static let locale = Locale(identifier: "en-US")

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    static var unavailableReason: String? {
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
                ? nil
                : "This Mac has no on-device speech model for \(locale.identifier)."
        }
        return "Transcribing needs macOS 26 or later."
    }

    /// Transcribe a recording.
    ///
    /// - Parameter vocabulary: this practice's own terms — drug names, local
    ///   spellings, the words a generic recogniser gets wrong. Passed as
    ///   contextual strings, which `docs/engineering/ASR.md` calls the cheapest
    ///   of the three levers for clinical vocabulary.
    static func transcribe(file: URL, vocabulary: [String]) async throws -> [RecognisedSegment] {
        if #available(macOS 26.0, *) {
            return try await recognise(file: file, vocabulary: vocabulary)
        }
        throw TranscriberError.needsNewerMac
    }

    // MARK: - macOS 26

    @available(macOS 26.0, *)
    private static func recognise(
        file: URL,
        vocabulary: [String]
    ) async throws -> [RecognisedSegment] {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriberError.notInstalled
        }

        // Asking for the audio time range is what makes a result attributable to
        // a moment in the recording, which is what the evidence margin needs.
        // Confidence comes along with it and is kept, because low confidence is
        // a useful flag for the reviewer.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )

        // The speech model is an OS asset, not something Klinote ships or
        // stores. On a Mac that has never used dictation it may not be present
        // yet; this asks the system to fetch it, once, on the user's behalf.
        // Klinote itself issues no request — see docs/compliance/PRIVACY.md.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw TranscriberError.audioUnreadable(error.localizedDescription)
        }

        let context = AnalysisContext()
        if !vocabulary.isEmpty {
            context.contextualStrings[.general] = vocabulary
        }

        // `init(inputAudioFile:finishAfterFile:)` takes the recording and starts
        // analysing it, and ends the results stream when it reaches the end.
        //
        // Do not also call `analyzeSequence(from:)`. That is the obvious-looking
        // pairing — the two appear side by side in the framework's headers — and
        // it starts the same file a second time: the process dies with SIGTRAP
        // inside the framework before a single result arrives. Measured on
        // macOS 26.6, not guessed. Await the results; that is the whole call.
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            analysisContext: context,
            finishAfterFile: true
        )

        let segments = try await collect(from: transcriber)

        // The analyzer must outlive the stream. Referencing it after the await
        // is what stops ARC releasing it the moment it stops being used.
        withExtendedLifetime(analyzer) {}

        guard !segments.isEmpty else { throw TranscriberError.nothingRecognised }
        return segments
    }

    @available(macOS 26.0, *)
    private static func collect(from transcriber: SpeechTranscriber) async throws -> [RecognisedSegment] {
        var segments: [RecognisedSegment] = []

        // Volatile results are the model thinking aloud; only finals are the
        // words it stands behind. `isFinal` is the framework's own answer, not
        // a guess from ordering.
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            segments.append(
                RecognisedSegment(
                    startMs: milliseconds(result.range.start),
                    endMs: milliseconds(result.range.end),
                    text: text,
                    confidence: confidence(of: result.text)
                )
            )
        }

        return segments
    }

    @available(macOS 26.0, *)
    private static func confidence(of text: AttributedString) -> Double? {
        for run in text.runs {
            if let value = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] {
                return value
            }
        }
        return nil
    }

    private static func milliseconds(_ time: CMTime) -> UInt64 {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return UInt64(seconds * 1000)
    }
}
