//
// AppModel.swift
//
// The shell's state. Deliberately thin: it holds selections and recording
// state, and delegates every clinical decision to the Rust engine.
//
// There is no network call anywhere in this file, and there must never be one.
//

import AppKit
import Foundation
import SwiftUI

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case paused(elapsedMs: UInt64)
    case finalising

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isActive: Bool { isRecording || isPaused }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isDrafting: Bool {
        if case .finalising = self { return true }
        return false
    }

    var word: String {
        switch self {
        case .idle: "Not recording"
        case .recording: "Recording"
        case .paused: "Paused"
        case .finalising: "Drafting"
        }
    }
}

enum NoteState: String {
    case draft, edited, approved, failed

    var word: String { rawValue.capitalized }

    var tone: Color {
        switch self {
        case .draft: NotaColor.secondary
        case .edited: NotaColor.ink
        case .approved: NotaColor.secondary
        case .failed: NotaColor.caution
        }
    }
}

struct Encounter: Identifiable {
    let id: String
    var patientRef: String
    var discipline: String
    var templateId: String
    var startedAt: Date
    var state: NoteState
    var note: ClinicalNote?
    var transcript: Transcript?
    /// True when the note was produced from the bundled sample rather than a
    /// real recording. The interface must say so, in the document itself.
    var isSyntheticDemo: Bool

    var durationMs: UInt64? {
        guard let transcript else { return nil }
        return transcript.segments.map(\.endMs).max()
    }

    /// What the menu bar shows: time and template, never an opaque code.
    var menuTitle: String {
        let time: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: startedAt)
        }()
        if isSyntheticDemo {
            return "Sample · \(templateId) · \(state.word)"
        }
        return "\(time) · \(templateId) · \(state.word)"
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var encounters: [Encounter] = []
    @Published var selection: String?
    @Published var recordingState: RecordingState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var traceLevel: Double = 0
    @Published var selectedSentenceID: String?
    @Published var discipline = "general_practice"
    @Published var templateId = "soap"
    @Published var lastError: String?
    @Published var isFiling = false
    @Published var isCopying = false
    @Published var isSwapping = false
    @Published var templates: [TemplateSummary] = []
    /// Until encryption at rest exists, recording real patients is forbidden.
    @AppStorage("nota.teachingBuildAcknowledged") var teachingBuildAcknowledged = false

    /// A recording captured before the speech model finished downloading,
    /// held until the download completes so it is transcribed for real.
    private var pendingRecording: URL?
    /// When the current (or just-finished) recording started.
    private var recordingStart: Date?

    private var downloadObserver: NSObjectProtocol?
    private var ticker: Timer?

    private init() {
        // When the first-use model finishes downloading, transcribe anything
        // we're holding.
        downloadObserver = NotificationCenter.default.addObserver(
            forName: .notaModelDownloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleDownloadFinished()
            }
        }
    }

    // MARK: - Selected encounter

    var selectedEncounter: Encounter? {
        guard let selection else { return encounters.first }
        return encounters.first { $0.id == selection } ?? encounters.first
    }

    // MARK: - Startup

    func bootstrap() {
        if let loaded = try? NotaCore.templates() {
            templates = loaded
        }
        prepareDemoNote()
    }

    /// Generates the bundled sample note so the window has real, honest content
    /// on first launch — and so a clinician sees a draft before ever recording
    /// a patient.
    func prepareDemoNote() {
        guard encounters.isEmpty else { return }
        guard
            let url = Bundle.main.url(forResource: "demo-transcript", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            lastError = "The bundled demonstration transcript is missing from the app."
            return
        }
        do {
            let result = try NotaCore.note(
                fromText: text,
                templateId: templateId,
                discipline: discipline,
                patientRef: "demo-0001"
            )
            var encounter = Encounter(
                id: result.note.encounterId,
                patientRef: "demo-0001",
                discipline: discipline,
                templateId: templateId,
                startedAt: Date(),
                state: .draft,
                note: result.note,
                transcript: result.transcript,
                isSyntheticDemo: true
            )
            if let duration = encounter.durationMs {
                encounter.startedAt = Date().addingTimeInterval(-Double(duration) / 1000)
            }
            encounters = [encounter]
            selection = encounter.id
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if recordingState.isDrafting { return }
        if recordingState.isActive {
            stopAndDraft()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard recordingState.isIdle else { return }
        guard teachingBuildAcknowledged else {
            lastError = "This build must not record real patients (nothing is encrypted at rest). Acknowledge that in Settings → Privacy, then record."
            return
        }
        switch ModelDownloader.shared.state {
        case .ready:
            break
        case .missing:
            lastError = "Download the speech engine first (Settings → Recording). It stays on this Mac — 465 MB, once."
            return
        case .downloading:
            lastError = "The speech engine is still downloading. Record when Settings says it is ready."
            return
        case .failed:
            lastError = "The speech engine could not be downloaded. Retry in Settings → Recording."
            return
        }
        Task { @MainActor in
            if !Recorder.shared.permissionGranted {
                guard await Recorder.shared.requestPermission() else {
                    lastError = "Microphone access is required to record. Enable it in System Settings → Privacy & Security → Microphone."
                    return
                }
            }
            do {
                _ = try Recorder.shared.start()
            } catch {
                lastError = "Could not start the microphone. Check that no other app has exclusive access to it."
                return
            }
            lastError = nil
            recordingStart = Date()
            RecordingStripController.shared.show(model: self)
            recordingState = .recording(startedAt: Date())
            elapsed = 0
            startTicker()
        }
    }

    func pauseRecording() {
        guard recordingState.isRecording else { return }
        Recorder.shared.pause()
        recordingState = .paused(elapsedMs: UInt64(elapsed * 1000))
        stopTicker()
        traceLevel = 0
    }

    func resumeRecording() {
        guard recordingState.isPaused else { return }
        do {
            try Recorder.shared.resume()
        } catch {
            lastError = "Could not resume the microphone."
            return
        }
        recordingState = .recording(startedAt: Date().addingTimeInterval(-elapsed))
        startTicker()
    }

    /// Stop capture and draft. The strip stays up with "Drafting" until the
    /// note is ready — a silent stall is how a GP loses the 90-second window.
    func stopAndDraft() {
        guard recordingState.isActive else { return }
        stopTicker()
        traceLevel = 0
        recordingState = .finalising

        Recorder.shared.stop()
        let url = Recorder.shared.capturedFile()
        let startedAt = recordingStart ?? Date()
        recordingStart = nil

        guard let url else {
            RecordingStripController.shared.hide()
            recordingState = .idle
            lastError = "No audio was captured."
            return
        }

        transcribe(url, startedAt: startedAt)
    }

    /// Transcribe a captured recording on a background queue (the FFI call
    /// blocks for the whole consultation and must never hold the main actor).
    private func transcribe(_ url: URL, startedAt: Date) {
        let templateId = self.templateId
        let discipline = self.discipline
        let patientRef = nextPatientRef()
        let modelPath = ModelDownloader.modelFile

        Task.detached {
            do {
                let result = try NotaCore.note(
                    fromAudio: url,
                    modelPath: modelPath,
                    templateId: templateId,
                    discipline: discipline,
                    patientRef: patientRef
                )
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    let encounter = Encounter(
                        id: result.note.encounterId,
                        patientRef: patientRef,
                        discipline: discipline,
                        templateId: templateId,
                        startedAt: startedAt,
                        state: .draft,
                        note: result.note,
                        transcript: result.transcript,
                        isSyntheticDemo: false
                    )
                    self.encounters.removeAll { $0.isSyntheticDemo }
                    self.encounters.insert(encounter, at: 0)
                    self.selection = encounter.id
                    self.pendingRecording = nil
                    self.lastError = nil
                    self.recordingState = .idle
                    self.elapsed = 0
                    RecordingStripController.shared.hide()
                    ReviewWindowController.shared.show()
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.pendingRecording = nil
                    self.lastError = "Couldn't draft this recording. Record again if you still need the note."
                    self.recordingState = .idle
                    self.elapsed = 0
                    RecordingStripController.shared.hide()
                }
            }
        }
    }

    func fileSelectedNote() {
        guard var encounter = selectedEncounter else { return }
        isFiling = true
        encounter.state = .approved
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        isFiling = false
    }

    /// Puts the engine Markdown on the clipboard so it can be pasted into the record.
    func copySelectedNote() {
        guard let note = selectedEncounter?.note else { return }
        isCopying = true
        defer { isCopying = false }
        do {
            let markdown = try NotaCore.markdown(for: note)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
        } catch {
            lastError = "Couldn't copy the note."
        }
    }

    /// Swap clinician and patient, then rebuild the note. Keyboard: ⌥⌘S.
    func swapSpeakersAndRedraft() {
        guard var encounter = selectedEncounter, var transcript = encounter.transcript else { return }
        guard !encounter.isSyntheticDemo else { return }
        isSwapping = true
        transcript.swapClinicianAndPatient()
        let templateId = encounter.templateId
        Task.detached {
            do {
                let note = try NotaCore.note(fromTranscript: transcript, templateId: templateId)
                await MainActor.run {
                    encounter.note = note
                    encounter.transcript = transcript
                    encounter.state = .draft
                    if let index = self.encounters.firstIndex(where: { $0.id == encounter.id }) {
                        self.encounters[index] = encounter
                    }
                    self.selectedSentenceID = nil
                    self.isSwapping = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Couldn't rebuild the note after swapping speakers."
                    self.isSwapping = false
                }
            }
        }
    }

    /// Mint an opaque pseudonymous encounter code. Never a name or MRN.
    private func nextPatientRef() -> String {
        "enc-\(UUID().uuidString.prefix(8))"
    }

    private func handleDownloadFinished() {
        guard let pendingRecording else { return }
        let startedAt = recordingStart ?? Date()
        self.pendingRecording = nil
        transcribe(pendingRecording, startedAt: startedAt)
    }

    func markEdited() {
        guard var encounter = selectedEncounter, encounter.state == .draft else { return }
        encounter.state = .edited
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
    }

    // MARK: - Derived

    var menuBarSymbol: String {
        if recordingState.isRecording { return "waveform.circle.fill" }
        if recordingState.isPaused { return "pause.circle" }
        return "waveform.circle"
    }

    var completenessLine: String {
        guard let note = selectedEncounter?.note else { return "" }
        let total = note.sections.count
        let filled = note.sections.filter { !$0.body.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if note.missingRequired.isEmpty {
            return "\(filled) of \(total) sections documented · no required section missing"
        }
        let names = note.missingRequired.map { key in
            note.sections.first { $0.key == key }?.title ?? key
        }
        return "\(filled) of \(total) sections documented · missing: \(names.joined(separator: ", "))"
    }

    var isSynthetic: Bool { selectedEncounter?.isSyntheticDemo ?? false }

    // MARK: - Ticker

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .recording(let startedAt) = self.recordingState {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
                self.traceLevel = Recorder.shared.inputLevel
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

enum NotaWindowID {
    static let review = "nota.review"
}
