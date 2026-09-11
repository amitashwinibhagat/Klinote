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
    @Published var traceSamples: [Double] = Array(repeating: 0, count: 64)
    @Published var selectedSentenceID: String?
    @Published var discipline = "general_practice"
    @Published var templateId = "soap"
    @Published var lastError: String?
    @Published var isFiling = false
    @Published var isCopying = false
    @Published var copyBanner: String?
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
        loadPersistedSessions()
        if encounters.isEmpty {
            prepareDemoNote()
        }
        selectFirstEvidence()
    }

    /// Opens the letter on first launch so the aha is not hidden behind the menu bar.
    func revealLetterIfFirstLaunch() {
        let key = "nota.didRevealLetter"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        ReviewWindowController.shared.show()
    }

    private func loadPersistedSessions() {
        guard let sessions = try? NotaCore.loadSessions() else { return }
        let mapped: [Encounter] = sessions.compactMap { session in
            guard let note = session.note, let transcript = session.transcript else { return nil }
            let started = Self.parseTime(session.startedAt) ?? Date()
            let synthetic = session.patientRef.hasPrefix("demo-")
            let state: NoteState
            switch note.reviewState {
            case "approved": state = .approved
            case "edited": state = .edited
            default: state = .draft
            }
            return Encounter(
                id: note.encounterId,
                patientRef: session.patientRef,
                discipline: session.discipline,
                templateId: session.templateId,
                startedAt: started,
                state: state,
                note: note,
                transcript: transcript,
                isSyntheticDemo: synthetic
            )
        }
        let reals = mapped.filter { !$0.isSyntheticDemo }
        encounters = reals.isEmpty ? mapped : reals
        selection = encounters.first?.id
    }

    private static func parseTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    func persist(_ encounter: Encounter) {
        guard let note = encounter.note, let transcript = encounter.transcript else { return }
        try? NotaCore.saveSession(
            patientRef: encounter.patientRef,
            discipline: encounter.discipline,
            templateId: encounter.templateId,
            startedAt: encounter.startedAt,
            note: note,
            transcript: transcript
        )
    }

    func selectFirstEvidence() {
        guard let note = selectedEncounter?.note else { return }
        if let first = note.sections.flatMap(\.sentences).first {
            selectedSentenceID = first.id
        }
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
            persist(encounter)
            selectFirstEvidence()
            let encounterId = encounter.id
            let transcript = result.transcript
            let template = templates.first(where: { $0.id == templateId }) ?? templates.first
            let fallback = result.note
            Task.detached {
                let drafted = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: fallback
                )
                await MainActor.run {
                    if let index = self.encounters.firstIndex(where: { $0.id == encounterId }) {
                        self.encounters[index].note = drafted
                        self.persist(self.encounters[index])
                        self.selectFirstEvidence()
                    }
                }
            }
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
        switch ModelDownloader.shared.noteState {
        case .ready:
            break
        case .missing:
            lastError = "Download Quire first (Settings → Recording). 1.9 GB, once, stays on this Mac."
            return
        case .downloading:
            lastError = "The note engine is still downloading. Record when Settings says it is ready."
            return
        case .failed:
            lastError = "The note engine could not be downloaded. Retry in Settings → Recording."
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
                let template = await MainActor.run {
                    self.templates.first(where: { $0.id == templateId }) ?? self.templates.first
                }
                let note = await Self.preferLocalDraft(
                    transcript: result.transcript,
                    template: template,
                    fallback: result.note
                )
                await MainActor.run {
                    let encounter = Encounter(
                        id: result.note.encounterId,
                        patientRef: patientRef,
                        discipline: discipline,
                        templateId: templateId,
                        startedAt: startedAt,
                        state: .draft,
                        note: note,
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
                    self.persist(encounter)
                    self.selectFirstEvidence()
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
        persist(encounter)
        isFiling = false
    }

    /// Local GGUF first, then Apple Foundation Models, then the rule-based note.
    nonisolated private static func preferLocalDraft(
        transcript: Transcript,
        template: TemplateSummary?,
        fallback: ClinicalNote
    ) async -> ClinicalNote {
        if let template, LocalLlm.isReady,
           let drafted = try? LocalLlm.draft(transcript: transcript, template: template) {
            return drafted
        }
        if let template,
           let drafted = await NoteDrafter.draft(
            transcript: transcript,
            template: template,
            encounterId: fallback.encounterId
           ) {
            return drafted
        }
        return fallback
    }

    /// Puts the engine Markdown on the clipboard so it can be pasted into the record.
    func copySelectedNote() {
        guard let note = selectedEncounter?.note else { return }
        do {
            let markdown = try NotaCore.markdown(for: note)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            isCopying = true
            copyBanner = "Copied — paste into the record"
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.isCopying = false
                if self.copyBanner?.hasPrefix("Copied") == true {
                    self.copyBanner = nil
                }
            }
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
        let template = templates.first(where: { $0.id == templateId }) ?? templates.first
        Task.detached {
            do {
                let rules = try NotaCore.note(fromTranscript: transcript, templateId: templateId)
                let note = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: rules
                )
                await MainActor.run {
                    encounter.note = note
                    encounter.transcript = transcript
                    encounter.state = .draft
                    if let index = self.encounters.firstIndex(where: { $0.id == encounter.id }) {
                        self.encounters[index] = encounter
                    }
                    self.persist(encounter)
                    self.selectFirstEvidence()
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
                self.traceSamples = Recorder.shared.trace
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
