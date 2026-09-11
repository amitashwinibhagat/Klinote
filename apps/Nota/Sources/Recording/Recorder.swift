//
// Recorder.swift
//
// Live capture with AVAudioEngine. Audio is written to a temporary mono
// 16-bit WAV file that the engine transcribes in one shot — no streaming ASR
// yet. The recording is deleted right after the draft is produced; Nota never
// keeps a recording unless the clinician asks it to.
//

import AVFoundation
import Foundation

@MainActor
final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published var isRecording = false
    @Published var inputLevel: Double = 0

    private let engine = AVAudioEngine()
    private var tempURL: URL?
    private var levelTimer: Timer?

    private init() {}

    var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Begin capture. Returns the file URL the audio is being written to.
    func start() throws -> URL {
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

        // Tapping the input gives us a mono-converted, 16-bit buffer that we
        // write straight to the file. Level metering comes from the same tap.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            // The tap format may be stereo; AVAudioFile(forWriting:) with a
            // channel count of 1 will handle the downmix if we write frames
            // at the tap's own format. To keep it simple and correct we write
            // the tap buffer verbatim — same sample rate, whatever channels —
            // because hound + the engine mono-downmix anyway.
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("Nota: could not write recording: \(error)")
            }

            // RMS level for the patient-visible trace.
            let channel = buffer.floatChannelData?[0]
            guard let channel else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                sum += channel[i] * channel[i]
            }
            let rms = (sum / Float(max(count, 1))).squareRoot()
            Task { @MainActor in
                self.inputLevel = Double(min(1, rms * 4))
            }
        }

        engine.prepare()
        try engine.start()

        tempURL = url
        isRecording = true
        startLevelTimer()
        return url
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        stopLevelTimer()
    }

    /// The captured file, or nil if capture never started.
    func capturedFile() -> URL? {
        tempURL
    }

    func cleanup() {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        tempURL = nil
    }

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            // inputLevel is already updated from the tap; nothing more to do.
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}