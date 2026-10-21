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

import CryptoKit
import Foundation

extension Notification.Name {
    /// Posted on the main thread when the note model finishes downloading.
    ///
    /// A note already written by the built-in rules is written again from its
    /// stored transcript the moment this lands, which is the only reason it
    /// exists.
    static let klinoteNoteModelDownloadFinished = Notification.Name("one.klinote.mac.note-model-download-finished")
}

enum ModelDownloadError: LocalizedError {
    case http(Int)
    case wrongSize(expected: Int64, got: Int64)
    case notGGUF
    case checksum

    var errorDescription: String? {
        switch self {
        case .http(let status): "The server answered with HTTP \(status)."
        case .wrongSize(let expected, let got):
            "The download was \(got) bytes; the model is \(expected)."
        case .notGGUF: "The download is not a GGUF model."
        case .checksum: "The download did not match the pinned model checksum."
        }
    }
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
    /// SHA-256 of the pinned GGUF. Set from the published file, so a changed
    /// upstream or an error page cannot be loaded as the note model.
    static let noteSHA256 = "0ce20058cc0ed6b6c9213bb383589327e458c12ffce0842fc96867042d669c75"

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
        // Hashing a 1.9 GB file on the main queue would freeze the app at the
        // moment the model arrives. The delegate does its file work here and
        // hops to the main actor only to publish state.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "one.klinote.mac.model-download"
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        refresh()
    }

    func refresh() {
        Self.adoptLegacyNoteFileIfNeeded()
        if Self.isPlausibleModel(at: Self.noteFile) {
            if case .downloading = noteState {} else { noteState = .ready }
        } else if FileManager.default.fileExists(atPath: Self.noteFile.path) {
            // A truncated, empty, or non-GGUF file is not a model. Removing it
            // here is what lets the next download start instead of every note
            // failing against a file that looks present.
            try? FileManager.default.removeItem(at: Self.noteFile)
            noteState = .missing
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
            // URLSession calls this for an error page too. A 404 body is not a
            // GGUF, and saving it as `quire.gguf` made the app say "Ready" and
            // then fail every note. Status, size, magic and hash are all
            // checked before the file is allowed to become the model.
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw ModelDownloadError.http(response.statusCode)
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value
            guard size == Self.noteExpectedSize else {
                throw ModelDownloadError.wrongSize(expected: Self.noteExpectedSize, got: size ?? 0)
            }
            guard Self.hasGGUFMagic(at: location) else {
                throw ModelDownloadError.notGGUF
            }
            guard try Self.sha256(of: location) == Self.noteSHA256 else {
                throw ModelDownloadError.checksum
            }

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

    /// A cheap sanity check for a file that is already on disk. The full hash
    /// is checked when a download lands; hashing 1.9 GB at every launch would
    /// delay the first note for no benefit.
    nonisolated static func isPlausibleModel(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size == noteExpectedSize && hasGGUFMagic(at: url)
    }

    nonisolated static func hasGGUFMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data("GGUF".utf8)
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
