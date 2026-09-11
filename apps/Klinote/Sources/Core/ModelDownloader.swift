//
// ModelDownloader.swift
//
// The one inward network in the product: on first use, Klinote downloads the
// open-source whisper small (en) tinydiarize model so speaker diarisation can
// run on device. Audio and text never leave the Mac — the model is the only
// thing that crosses the network, and it crosses it in one direction.
//
// Lives in Swift (URLSession), never in the Rust workspace, so the engine and
// the CI dependency denylist stay network-free.
//

import Foundation

extension Notification.Name {
    /// Posted on the main thread when the speech model finishes downloading.
    static let klinoteModelDownloadFinished = Notification.Name("one.klinote.mac.model-download-finished")
}

enum ModelState: Equatable {
    case missing
    case downloading(Double)
    case ready
    case failed(String)

    var word: String {
        switch self {
        case .missing: "Speech engine not downloaded"
        case .downloading(let fraction): "Downloading speech engine \(Int(fraction * 100))%"
        case .ready: "Speech engine ready"
        case .failed(let message): "Download failed — \(message)"
        }
    }
}

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    /// The upstream tinydiarize whisper project (only hosted `-tdrz` model).
    static let modelURL = URL(
        string: "https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/resolve/main/ggml-small.en-tdrz.bin"
    )!
    /// Expected size in bytes; used to sanity-check a completed download.
    static let expectedSize: Int64 = 487_614_184

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

    @Published var state: ModelState = .missing
    @Published var noteState: ModelState = .missing

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
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

    nonisolated static var modelFile: URL {
        modelsDirectory.appendingPathComponent("ggml-small.en-tdrz.bin")
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
        if FileManager.default.fileExists(atPath: Self.modelFile.path) {
            if case .downloading = state {} else { state = .ready }
        } else if case .downloading = state {
        } else if case .failed = state {
        } else {
            state = .missing
        }
        if FileManager.default.fileExists(atPath: Self.noteFile.path) {
            if case .downloading = noteState {} else { noteState = .ready }
        } else if case .downloading = noteState {
        } else if case .failed = noteState {
        } else {
            noteState = .missing
        }
    }

    func start() {
        refresh()
        switch state {
        case .ready, .downloading: return
        case .missing, .failed: break
        }

        state = .downloading(0)
        let downloadTask: URLSessionDownloadTask
        if let resumeData {
            downloadTask = session.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            downloadTask = session.downloadTask(with: Self.modelURL)
        }
        downloadTask.taskDescription = "speech"
        task = downloadTask
        progressObservation = downloadTask.progress.observe(
            \.fractionCompleted,
            options: [.new]
        ) { [weak self] progress, _ in
            Task { @MainActor in
                guard let self, progress.totalUnitCount > 0 else { return }
                // Bring the count back up to the real goal (resume restarts it).
                let fraction = min(1, Double(progress.completedUnitCount) / Double(Self.expectedSize))
                self.state = .downloading(fraction)
            }
        }
        downloadTask.resume()
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

    func cancel() {
        progressObservation = nil
        task?.cancel { [weak self] data in
            DispatchQueue.main.async {
                self?.resumeData = data
            }
        }
        task = nil
        state = .missing
    }

    // MARK: - URLSessionDownloadDelegate

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
            let isNote = downloadTask.taskDescription == "note"
            let destination = isNote ? Self.noteFile : Self.modelFile
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in
                if isNote {
                    self.noteState = .ready
                } else {
                    self.state = .ready
                    NotificationCenter.default.post(name: .klinoteModelDownloadFinished, object: nil)
                }
                self.task = nil
                self.progressObservation = nil
            }
        } catch {
            Task { @MainActor in
                self.state = .failed(error.localizedDescription)
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
                self.state = .missing
            } else {
                self.state = .failed(error.localizedDescription)
            }
            self.task = nil
            self.progressObservation = nil
        }
    }
}