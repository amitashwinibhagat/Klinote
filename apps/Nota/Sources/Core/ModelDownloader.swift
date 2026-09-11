//
// ModelDownloader.swift
//
// The one inward network in the product: on first use, Nota downloads the
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
    static let notaModelDownloadFinished = Notification.Name("one.nota.mac.model-download-finished")
}

enum ModelState: Equatable {
    case missing
    case downloading(Double)
    case ready
    case failed(String)

    var word: String {
        switch self {
        case .missing: "Model not downloaded"
        case .downloading(let fraction): "Downloading speech model \(Int(fraction * 100))%"
        case .ready: "Speech model ready"
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

    @Published var state: ModelState = .missing

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var progressObservation: NSKeyValueObservation?

    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Nota/Models", isDirectory: true)
    }

    nonisolated static var modelFile: URL {
        modelsDirectory.appendingPathComponent("ggml-small.en-tdrz.bin")
    }

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "one.nota.mac.model-download"
        )
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        refresh()
    }

    func refresh() {
        if FileManager.default.fileExists(atPath: Self.modelFile.path) {
            state = .ready
        } else if case .downloading = state {
            // keep progress
        } else if case .failed = state {
            // keep the failure so the user can retry
        } else {
            state = .missing
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
            try FileManager.default.moveItem(at: location, to: Self.modelFile)
            Task { @MainActor in
                self.state = .ready
                self.task = nil
                self.progressObservation = nil
                NotificationCenter.default.post(name: .notaModelDownloadFinished, object: nil)
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