//
// Recorder.swift
//
// Live capture with AVAudioEngine. Audio is written to a temporary WAV that
// the engine transcribes in one shot. Pause actually pauses the engine — a
// paused strip must mean the microphone is not writing. The file is deleted
// after the draft is produced.
//

import AVFoundation
import Foundation

@MainActor
final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var inputLevel: Double = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var tempURL: URL?
    private var tapInstalled = false

    private init() {}

    var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Begin capture. Returns the file URL the audio is being written to.
    func start() throws -> URL {
        if engine.isRunning || tapInstalled {
            stop()
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nota-recording-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.file = file

        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("Nota: could not write recording: \(error)")
            }

            let channel = buffer.floatChannelData?[0]
            guard let channel else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                sum += channel[i] * channel[i]
            }
            let rms = (sum / Float(max(count, 1))).squareRoot()
            Task { @MainActor in
                self?.inputLevel = Double(min(1, rms * 4))
            }
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()

        tempURL = url
        isRecording = true
        isPaused = false
        return url
    }

    /// Pause the microphone. The file stays open so resume can continue it.
    func pause() {
        guard engine.isRunning else { return }
        engine.pause()
        isPaused = true
        isRecording = false
        inputLevel = 0
    }

    func resume() throws {
        guard isPaused else { return }
        try engine.start()
        isPaused = false
        isRecording = true
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        // Closing the file flushes headers.
        file = nil
        isRecording = false
        isPaused = false
        inputLevel = 0
    }

    func capturedFile() -> URL? {
        tempURL
    }

    func cleanup() {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        tempURL = nil
        file = nil
    }
}
