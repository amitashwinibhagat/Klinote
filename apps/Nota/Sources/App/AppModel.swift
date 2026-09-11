//
// AppModel.swift
//
// The shell's state. Deliberately thin: it holds selections and recording
// state, and delegates every clinical decision to the Rust engine.
//
// There is no network call anywhere in this file, and there must never be one.
//

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
    @Published var templates: [TemplateSummary] = []

    private var ticker: Timer?

    private init() {}

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
        if recordingState.isActive {
            stopAndDraft()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !recordingState.isActive else { return }
        RecordingStripController.shared.show(model: self)
        recordingState = .recording(startedAt: Date())
        elapsed = 0
        startTicker()
    }

    func pauseRecording() {
        guard recordingState.isRecording else { return }
        recordingState = .paused(elapsedMs: UInt64(elapsed * 1000))
        stopTicker()
        traceLevel = 0
    }

    func resumeRecording() {
        guard recordingState.isPaused else { return }
        recordingState = .recording(startedAt: Date().addingTimeInterval(-elapsed))
        startTicker()
    }

    func stopAndDraft() {
        guard recordingState.isActive else { return }
        stopTicker()
        traceLevel = 0
        recordingState = .finalising
        RecordingStripController.shared.hide()

        // M1 has no audio engine wired in yet: the draft is produced from the
        // bundled sample and labelled as synthetic in the document. When a real
        // ASR engine lands, this is the only method that changes.
        prepareDemoNote()
        recordingState = .idle
        elapsed = 0
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
                // A stand-in level so the trace is visibly alive. The real
                // meter arrives with the audio engine.
                self.traceLevel = 0.35 + 0.3 * abs(sin(self.elapsed * 1.7))
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
