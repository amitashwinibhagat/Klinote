//
// ModelDownloader.swift
//
// The one inward network in the product: on first use, Klinote downloads the
// open-source note model it calls Quire, so a draft can be written from the
// transcript. Audio and transcripts never leave the Mac — the model is the only
// thing that crosses the network, and it crosses it in one direction.
//
// Speech recognition is *not* here any more. It used to be: 465 MB of
// whisper.cpp model, downloaded before the app could transcribe anything. That
// is gone — `SpeechAnalyzer` is part of macOS and `Transcriber.swift` uses it,
// so listening needs no download and no model file at all. That also removed the
// two-download sequencing this file used to carry: one task slot, one queue
// flag, and the class of bug where a failed note download marked listening as
// failed and stopped consultations.
//
// Lives in Swift (URLSession), never in the Rust workspace, so the engine and
// the CI dependency denylist stay network-free.
//

import Foundation

extension Notification.Name {
    /// Posted on the main thread when the note model finishes downloading.
    ///
    /// A note already written by the built-in rules is written again from its
    /// stored transcript the moment this lands, which is the only reason it
    /// exists.
    static let klinoteNoteModelDownloadFinished = Notification.Name("one.klinote.mac.note-model-download-finished")
}

enum ModelState: Equatable {
    case missing
    case downloading(Double)
    case ready
    case failed(String)

    var word: String {
        switch self {
        case .missing: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100))%"
        case .ready: "Ready on this Mac"
        case .failed(let message): "Could not download — \(message)"
        }
    }
}

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    static let noteURL = URL(
        string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q3_K_S.gguf"
    )!
    /// ~1.89 GB. Ships on disk as quire.gguf — never the upstream filename.
    static let noteExpectedSize: Int64 = 1_886_997_600

    nonisolated static var noteFile: URL {
        modelsDirectory.appendingPathComponent("quire.gguf")
    }

    nonisolated static func adoptLegacyNoteFileIfNeeded() {
        let dest = noteFile
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        let legacy = modelsDirectory.appendingPathComponent(
            "Qwen3-4B-Instruct-2507-Q3_K_S.gguf"
        )
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.moveItem(at: legacy, to: dest)
    }

    @Published var noteState: ModelState = .missing
    /// Bytes received from the model download. The only number this product can
    /// honestly show, because arriving bytes are the only traffic there is —
    /// see `scripts/check-network-surface.sh`.
    @Published var bytesReceived: Int64 = 0
    @Published var downloadsCompleted: Int = 0

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dest = base.appendingPathComponent("Klinote", isDirectory: true)
        let legacy = base.appendingPathComponent("Nota", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dest.path),
           FileManager.default.fileExists(atPath: legacy.path)
        {
            try? FileManager.default.moveItem(at: legacy, to: dest)
        }
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }

    nonisolated static var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "one.klinote.mac.model-download"
        )
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        refresh()
    }

    func refresh() {
        Self.adoptLegacyNoteFileIfNeeded()
        if FileManager.default.fileExists(atPath: Self.noteFile.path) {
            if case .downloading = noteState {} else { noteState = .ready }
        } else if case .downloading = noteState {
        } else if case .failed = noteState {
        } else {
            noteState = .missing
        }
    }

    func startNote() {
        refresh()
        switch noteState {
        case .ready, .downloading: return
        case .missing, .failed: break
        }

        noteState = .downloading(0)
        let downloadTask = session.downloadTask(with: Self.noteURL)
        downloadTask.taskDescription = "note"
        task = downloadTask
        progressObservation = downloadTask.progress.observe(
            \.fractionCompleted,
            options: [.new]
        ) { [weak self] progress, _ in
            Task { @MainActor in
                guard let self else { return }
                let fraction = min(1, Double(progress.completedUnitCount) / Double(Self.noteExpectedSize))
                self.noteState = .downloading(fraction)
            }
        }
        downloadTask.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.bytesReceived = max(self.bytesReceived, totalBytesWritten)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let directory = Self.modelsDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = Self.noteFile
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in
                self.noteState = .ready
                NotificationCenter.default.post(
                    name: .klinoteNoteModelDownloadFinished, object: nil
                )
                self.downloadsCompleted += 1
                self.task = nil
                self.progressObservation = nil
            }
        } catch {
            Task { @MainActor in
                self.noteState = .failed(error.localizedDescription)
                self.task = nil
                self.progressObservation = nil
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            // Cancellation is a missing state, not a failure.
            if (error as NSError).code == NSURLErrorCancelled {
                self.noteState = .missing
            } else {
                self.noteState = .failed(error.localizedDescription)
            }
            self.task = nil
            self.progressObservation = nil
        }
    }
}
