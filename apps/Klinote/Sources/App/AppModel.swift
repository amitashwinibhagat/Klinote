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
    /// Deliberately not capturing: the sensitive aside, the third party, the
    /// disclosure. Different from pause because it is a documentation decision,
    /// and the note says so.
    case holding(elapsedMs: UInt64)
    case finalising

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isHolding: Bool {
        if case .holding = self { return true }
        return false
    }

    var isActive: Bool { isRecording || isPaused || isHolding }

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
        case .holding: "Off the record"
        case .finalising: "Writing"
        }
    }
}

/// Which job-screen the window is showing. The letter is not the caseload.
enum Workspace: Equatable {
    /// S0 — sample progress note, click a sentence.
    case sample
    /// S1 — how is this session getting in.
    case desk
    /// S4 — the progress note, only once there is a draft.
    case letter
    /// S6 — earlier sessions, when they asked.
    case earlier
}

enum CaptureKind: Equatable {
    /// Client in the room; they can see the lamp.
    case session
    /// Empty room; mic on the therapist.
    case dictate
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var encounters: [Encounter] = []
    /// Changing the consult changes which tasks the letter can show ticks for,
    /// so the index is rebuilt here rather than queried per sentence.
    @Published var selection: String? {
        didSet {
            guard oldValue != selection else { return }
            rebuildTaskIndex()
        }
    }
    @Published var recordingState: RecordingState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var traceLevel: Double = 0
    @Published var traceSamples: [Double] = Array(repeating: 0, count: 64)
    @Published var selectedSentenceID: String?
    @Published var discipline = "psychology"
    @Published var templateId = "psychology"
    @Published var lastError: String?
    @Published var isFiling = false
    /// Which consults are being written again right now.
    ///
    /// This was one flag for the whole app, so a rewrite already in flight
    /// silently cancelled the request for another consult — the paste redraft
    /// and a download finishing can overlap, and one of them simply did nothing.
    @Published private(set) var redrafting: Set<String> = []

    /// Whether the consult on screen is the one being written again.
    var isRedrafting: Bool {
        guard let id = selectedEncounter?.id else { return false }
        return redrafting.contains(id)
    }
    @Published var isCopying = false
    @Published var copyBanner: String?
    @Published var isSwapping = false
    @Published var isPasting = false
    /// The sentence currently open for correction, if any.
    @Published var editingSentenceID: String?
    @Published var templates: [TemplateSummary] = []
    /// First-run setup, which states the clinician's consent duty and offers
    /// the download as a choice rather than a wall.
    @AppStorage("klinote.didCompleteSetup") var didCompleteSetup = false
    /// Whether the first-run sheet is on screen. Deliberately separate from
    /// `didCompleteSetup`: acknowledging the consent duty has to be an explicit
    /// act by the clinician, never a side effect of a sheet being dismissed.
    /// Driving the sheet straight off `didCompleteSetup` meant any teardown the
    /// system performed wrote the acknowledgement for them.
    @Published var isSettingUp = false
    @Published var workspace: Workspace = .desk
    @Published var captureKind: CaptureKind = .session
    /// Type-or-paste on the desk, not a CLINICIAN:/PATIENT: sheet.
    @Published var isTyping = false
    @AppStorage("klinote.didSeeSample") var didSeeSample = false
    /// Record-the-session waits on the consent tick; dictate does not.
    private var pendingCapture: CaptureKind?

    /// Show the letter every time Klinote starts. On by default: launching an
    /// app should produce a window. Turn it off if you keep Klinote running in
    /// the menu bar all day.
    @AppStorage("klinote.openWindowAtLaunch") var openWindowAtLaunch = true

    /// Who is at the desk. A practice Mac may be shared, and a note that says
    /// "reviewed by you" is not a signature.
    @AppStorage("klinote.clinicianName") var clinicianName = ""
    @AppStorage("klinote.clinicianRegistration") var clinicianRegistration = ""
    /// Show every clinician's consults on a shared Mac. Off by default once a
    /// name is set, because my list should be mine.
    @AppStorage("klinote.showAllClinicians") var showAllClinicians = false

    /// The checklist and the ticks, derived from one store read.
    @Published private(set) var board = TaskBoard()

    /// Every read and write of the encrypted store. AppModel does not know
    /// about paths, keys or the C ABI.
    private let store = SessionStore()
    /// Set when a copy is requested for a consult that is not on screen. The
    /// clinician confirms before the clipboard changes.
    @Published var pendingCopy: Encounter?
    /// Set when print is requested for a consult that is not on screen.
    @Published var pendingPrint: Encounter?

    /// A recording captured before the speech model finished downloading,
    /// held until the download completes so it is transcribed for real.
    private var pendingRecording: URL?
    /// When the current (or just-finished) recording started.
    private var recordingStart: Date?
    /// When the current hold began, if one is running.
    private var holdStartedAt: Date?
    /// Total time deliberately not captured in the current recording.
    private var heldMs: UInt64 = 0

    private var downloadObserver: NSObjectProtocol?
    private var noteDownloadObserver: NSObjectProtocol?
    private var ticker: Timer?

    private init() {
        // When the first-use model finishes downloading, transcribe anything
        // we're holding.
        downloadObserver = NotificationCenter.default.addObserver(
            forName: .klinoteModelDownloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleDownloadFinished()
            }
        }

        // And when Quire arrives, rewrite the note on screen if the rules wrote
        // it. Quietly: the clinician pressed download, and the note improving
        // underneath them is the answer, not a dialogue.
        noteDownloadObserver = NotificationCenter.default.addObserver(
            forName: .klinoteNoteModelDownloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Rewrite the consult the download was asked for, not whatever
                // is selected by the time it lands. A 1.9 GB download takes long
                // enough to move to the next patient, and this used to rewrite
                // that note instead — a record the clinician never asked to
                // change, silently rewritten under a banner that said so.
                guard let self, let id = self.pendingRewriteID else { return }
                self.pendingRewriteID = nil
                guard self.noteIsWrittenByRules(id) else { return }
                await self.redraftWithNoteModel(id, announceFailure: true)
            }
        }
    }

    // MARK: - Selected encounter

    var selectedEncounter: Encounter? {
        guard let selection else { return encounters.first }
        return encounters.first { $0.id == selection } ?? encounters.first
    }

    /// Drafts that never made it into the record. The desk's only inbox.
    var uncopied: [Encounter] {
        encounters.filter { !$0.isSyntheticDemo && $0.state != .approved && $0.note != nil }
    }

    func showDesk() {
        didSeeSample = true
        isTyping = false
        workspace = .desk
    }

    func showEarlier() {
        didSeeSample = true
        workspace = .earlier
    }

    func openLetter(_ id: String) {
        selection = id
        workspace = .letter
    }

    func beginTyping() {
        workspace = .desk
        isTyping = true
        isPasting = false
    }

    func completeSetup() {
        didCompleteSetup = true
        isSettingUp = false
        pendingCapture = nil
    }

    func completeSetupThenRecord() {
        didCompleteSetup = true
        isSettingUp = false
        let pending = pendingCapture
        pendingCapture = nil
        if pending == .session {
            startRecording(kind: .session)
        }
    }

    // MARK: - Startup

    /// Months of history to keep. 0 means keep everything.
    @AppStorage("klinote.retentionMonths") var retentionMonths = 0

    /// Launch order matters here, and getting it wrong looked like a crash.
    ///
    /// Opening the encrypted store reads a key from the Keychain, and macOS
    /// will show a modal prompt for that when the app's signature does not
    /// match the item's ACL — which is every ad-hoc signed development build.
    /// That prompt blocks whoever asks for it. Asking on the main actor, before
    /// the window exists, meant no window ever appeared: just a menu-bar icon
    /// and a password dialog behind Terminal.
    ///
    /// So: window first, store second, and the store off the main actor.
    func bootstrap() {
        if let loaded = try? KlinoteCore.templates() {
            templates = loaded
        }
        openWindowIfNeeded()
        Task { await loadStoredData() }
    }

    /// Why the store could not be opened. Silence here would look like lost
    /// history rather than a denied key. (nil means all is well.)
    @Published var storeError: String?

    private func loadStoredData() async {
        let months = retentionMonths
        let store = self.store
        let outcome = await Task.detached(priority: .userInitiated) { () -> StoredWorld? in
            do { return try store.load(retentionMonths: months) } catch {
                NSLog("Klinote: could not read the store: %@", error.localizedDescription)
                return nil
            }
        }.value

        // A store that cannot be read is a banner, not a dead end. The letter
        // below still opens, with the sample in it, because a clinician who
        // denied the Keychain prompt should be told what happened rather than
        // shown an empty window.
        let world = outcome ?? StoredWorld()
        storeError = outcome == nil
            ? "The encrypted store could not be read. Your sessions are still on this Mac."
            : nil
        applySessions(world.sessions)
        rebuildBoard(tasks: world.tasks)
        if world.purgedNotes > 0 {
            copyBanner = world.purgedNotes == 1
                ? "Deleted 1 note past the retention period."
                : "Deleted \(world.purgedNotes) notes past the retention period."
        }
        if encounters.isEmpty {
            prepareDemoNote()
        }
        // Returning users already passed first-run; do not bounce them into
        // the sample. New users see the sample letter, not a setup wall.
        if didCompleteSetup {
            didSeeSample = true
            workspace = .desk
        } else if !didSeeSample {
            workspace = .sample
        } else {
            workspace = .desk
        }
        selectFirstEvidence()
    }

    /// Opens the letter on first launch so the aha is not hidden behind the menu bar.
    /// Open the letter when Klinote starts.
    ///
    /// Two reasons it must, and neither is a preference:
    /// * setup is not finished, and the setup sheet lives on this window;
    /// * someone double-clicked the app, and an app that opens to nothing but
    ///   a menu-bar icon looks broken.
    ///
    /// The old behaviour gated this on a one-shot flag written before the
    /// window was even created. Preferences live outside the app bundle, so
    /// reinstalling never cleared it, and there was no way back to the
    /// first-run state short of deleting the plist by hand.
    /// Whether launching should produce a window — and therefore whether the
    /// app should start as a regular app rather than a menu-bar accessory.
    var opensWindowAtLaunch: Bool { !didCompleteSetup || openWindowAtLaunch }

    func openWindowIfNeeded() {
        if opensWindowAtLaunch {
            ReviewWindowController.shared.show()
            ReviewWindowController.shared.closeStraySettingsWindow()
        }
        // Setup is not first paint. The sample letter is. Consent lives on
        // the record-the-session path only.
    }

    private func applySessions(_ sessions: [StoredSession]) {
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
                clinicianRef: session.clinicianRef,
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

    /// Retention runs at launch and on demand. A real delete, not a flag.
    @discardableResult
    func purgeExpiredNotes() -> Int {
        let removed = (try? store.purge(months: retentionMonths)) ?? 0
        if removed > 0 {
            copyBanner = removed == 1
                ? "Deleted 1 note past the retention period."
                : "Deleted \(removed) notes past the retention period."
        }
        return removed
    }

    /// Text → note, with no model and no download. The fastest honest path to
    /// a letter: paste what was said, get a draft in the template.
    func makeNote(fromPastedText text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Nothing was pasted."
            return
        }
        isPasting = false
        let patientRef = "pasted-\(UUID().uuidString.prefix(6))"
        let (text, learned) = LearnedTerms.apply(to: trimmed)
        do {
            let result = try KlinoteCore.note(
                fromText: text,
                templateId: templateId,
                discipline: discipline,
                patientRef: patientRef
            )
            let encounter = Encounter(
                id: result.note.encounterId,
                patientRef: patientRef,
                discipline: discipline,
                templateId: templateId,
                startedAt: Date(),
                state: .draft,
                note: result.note,
                transcript: result.transcript,
                isSyntheticDemo: false
            )
            encounters.insert(encounter, at: 0)
            selection = encounter.id
            persist(encounter)
            selectFirstEvidence()
            syncTasks(for: encounter)
            isTyping = false
            workspace = .letter
            // A pasted consult was written by the rules and never offered to a
            // model, so a clinician who pasted rather than recorded got the
            // thin draft even with Quire installed. The note appears at once —
            // nobody should wait on a model to see their own words — and is
            // written again when the model has finished with it.
            if aModelCouldWriteThis {
                Task { @MainActor in
                    await self.redraftWithNoteModel(encounter.id)
                }
            }
            if learned > 0 {
                copyBanner = learned == 1
                    ? "1 learned correction applied."
                    : "\(learned) learned corrections applied."
            } else {
                promptPasteIfReady()
            }
            ReviewWindowController.shared.show()
        } catch {
            lastError = "Could not read that transcript. Check it has CLINICIAN: and PATIENT: lines."
        }
    }

    /// The other things this consult already owes. Same transcript, different
    /// template — the letter is derived, never a second recording.
    var documentTemplates: [TemplateSummary] {
        templates.filter(\.isDocument)
    }

    var noteTemplates: [TemplateSummary] {
        templates.filter { !$0.isDocument }
    }

    func reloadTemplates() {
        if let loaded = try? KlinoteCore.templates() {
            templates = loaded
        }
    }

    /// Print, with the same wrong-consult guard as copy. Printing the wrong
    /// note puts it on paper, where it cannot be recalled.


    func requestPrintFromSelection() {
        guard let id = selection else { return }
        request(.print, of: id)
    }

    /// Print exactly what Copy note would have put on the clipboard.
    func printSelectedNote() {
        guard let encounter = selectedEncounter, let note = encounter.note else { return }
        PrintNote.run(
            for: note,
            patientRef: encounter.patientRef,
            title: displayName(for: encounter)
        )
    }

    /// Encounters grouped by the day they happened, newest first.
    ///
    /// A flat list is fine at five consults and useless at fifty, which is one
    /// clinic week. Grouping also answers "what did I do on Tuesday?" without
    /// a filter UI.
    func encounterGroups(matching query: String) -> [EncounterGrouping.Group] {
        EncounterGrouping.groups(
            from: encounters,
            matching: query,
            today: Date(),
            clinician: clinicianName,
            showAllClinicians: showAllClinicians
        )
    }

    /// A friendly label for the sidebar: the template's own name.
    func displayName(for encounter: Encounter) -> String {
        if let template = templates.first(where: { $0.id == encounter.templateId }) {
            return template.name
        }
        return encounter.templateId == "psychology" ? "Therapy session note" : "Progress note"
    }

    func makeDocument(from encounterID: String, templateId: String) {
        guard let source = encounters.first(where: { $0.id == encounterID }),
              let transcript = source.transcript,
              let template = templates.first(where: { $0.id == templateId })
        else { return }
        do {
            let rules = try KlinoteCore.note(fromTranscript: transcript, templateId: templateId)
            var document = Encounter(
                id: rules.encounterId,
                patientRef: source.patientRef,
                discipline: source.discipline,
                templateId: templateId,
                startedAt: source.startedAt,
                state: .draft,
                note: rules,
                transcript: transcript,
                isSyntheticDemo: source.isSyntheticDemo
            )
            document.isDerived = true
            encounters.insert(document, at: 0)
            selection = document.id
            persist(document)
            selectFirstEvidence()
            let fallback = rules
            Task.detached {
                let drafted = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: fallback
                )
                await MainActor.run {
                    if let index = self.encounters.firstIndex(where: { $0.id == document.id }) {
                        // Same reason as the redraft: a line typed into the
                        // document while the model was working is in no
                        // transcript, so it has to be carried across.
                        let current = self.encounters[index].note
                        self.encounters[index].note = current.map {
                            NoteEditing.carryingAuthoredLines(from: $0, into: drafted)
                        } ?? drafted
                        self.persist(self.encounters[index])
                        self.selectFirstEvidence()
                    }
                }
            }
        } catch {
            lastError = "Could not write that document from this session."
        }
    }

    func renameEncounter(_ id: String, to patientRef: String) {
        let trimmed = patientRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = encounters.firstIndex(where: { $0.id == id }) else { return }
        encounters[index].patientRef = trimmed
        persist(encounters[index])
    }

    func deleteEncounter(_ id: String) {
        // The bundled sample was never recorded, so there is nothing in the
        // store to remove for it.
        let isBundledSample = encounters.contains { $0.id == id && $0.isSyntheticDemo }
        if !isBundledSample {
            try? store.delete(encounterID: id)
        }
        encounters.removeAll { $0.id == id }
        if selection == id {
            selection = encounters.first?.id
            selectedSentenceID = nil
            selectFirstEvidence()
        }
    }

    func persist(_ encounter: Encounter) {
        try? store.save(encounter, clinician: clinicianName)
        // Keeps the derived lists in step with the consult list without
        // another store read: this is all in memory.
        rebuildTaskViews()
    }

    // MARK: - Tasks

    /// One row per sentence in a section the template marks as work to do.
    ///
    /// Called after a note is drafted. It never deletes: a task the clinician
    /// ticked stays ticked even if the note is re-drafted.
    func syncTasks(for encounter: Encounter) {
        guard let note = encounter.note else { return }
        for section in note.sections {
            let isAction = templates
                .first { $0.id == encounter.templateId }?
                .sections.first { $0.key == section.key }?
                .actions ?? false
            guard isAction else { continue }
            for sentence in section.sentences {
                try? store.addTask(
                    encounterID: encounter.id,
                    text: sentence.text,
                    sourceKey: section.key
                )
            }
        }
        reloadTasks()
    }

    /// One store read. Everything below is derived in memory from this.
    ///
    /// The shell used to open the encrypted store once per sentence per
    /// render — each open a Keychain lookup, an SQLCipher key derivation and
    /// (until this change) the whole schema. Measured at 63 ms a call, that
    /// was roughly 800 ms of blocked main thread every time a clinician
    /// clicked a sentence in a thirteen-sentence note. The store is not free,
    /// so it is read once and the answers are kept.
    func reloadTasks() {
        rebuildBoard(tasks: (try? KlinoteCore.tasks(encounterId: "")) ?? [])
    }

    /// One read fills the board; everything the interface shows is derived.
    private func rebuildBoard(tasks: [ConsultTask]) {
        board = TaskBoard.build(tasks: tasks, encounters: encounters, selection: selection)
    }

    /// The consult list or the selection changed. Rebuilt from what is already
    /// in memory — never another read.
    private func rebuildTaskViews() {
        rebuildBoard(tasks: board.all)
    }

    private func rebuildTaskIndex() {
        rebuildTaskViews()
    }

    /// The task a given sentence became, if its section is work to do.
    ///
    /// A dictionary lookup. This is called from a view body, once per
    /// sentence, so it must never touch the store.
    func task(for encounterID: String, sentence: String) -> ConsultTask? {
        guard encounterID == selection else { return nil }
        return board.task(for: sentence, in: encounterID)
    }

    func setTask(_ task: ConsultTask, done: Bool) {
        try? store.setTaskDone(id: task.id, done: done)
        reloadTasks()
    }

    func deleteTask(_ task: ConsultTask) {
        try? store.deleteTask(id: task.id)
        reloadTasks()
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
            lastError = "The sample note is missing from the app."
            return
        }
        do {
            let result = try KlinoteCore.note(
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

    func togglePause() {
        guard recordingState.isActive else { return }
        if recordingState.isPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    /// The Consult menu acts on whatever is selected in the sidebar.
    func makeDocumentFromSelection(_ templateId: String) {
        guard let id = selection else { return }
        makeDocument(from: id, templateId: templateId)
    }

    func toggleRecording() {
        if recordingState.isDrafting { return }
        if recordingState.isActive {
            stopAndDraft()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        startRecording(kind: .session)
    }

    func startDictating() {
        startRecording(kind: .dictate)
    }

    func startRecording(kind: CaptureKind) {
        guard recordingState.isIdle else { return }
        captureKind = kind
        if kind == .session && !didCompleteSetup {
            pendingCapture = .session
            isSettingUp = true
            return
        }
        switch ModelDownloader.shared.state {
        case .ready:
            break
        case .missing:
            lastError = "Download listening first (Settings → Recording). 465 MB, once, stays on this Mac."
            return
        case .downloading:
            lastError = "Listening is still downloading. Record when Settings says it is ready."
            return
        case .failed:
            lastError = "Listening could not be downloaded. Retry in Settings → Recording."
            return
        }
        // Quire is an upgrade, not a ticket. Without it the rule-based engine
        // still produces a note from the transcript, and AFM is tried first.
        Task { @MainActor in
            if !Recorder.shared.permissionGranted {
                guard await Recorder.shared.requestPermission() else {
                    lastError = "Allow the microphone in System Settings → Privacy & Security → Microphone."
                    return
                }
            }
            do {
                _ = try Recorder.shared.start()
            } catch {
                lastError = "Could not start the microphone. Another app may be using it."
                return
            }
            lastError = nil
            recordingStart = Date()
            heldMs = 0
            holdStartedAt = nil
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

    /// Hold means "do not document this". Capture stops, and the milliseconds
    /// are counted so the note can say a gap was deliberate.
    func holdRecording() {
        guard recordingState.isRecording else { return }
        Recorder.shared.pause()
        recordingState = .holding(elapsedMs: UInt64(elapsed * 1000))
        holdStartedAt = Date()
        stopTicker()
        traceLevel = 0
    }

    func endHold() {
        guard recordingState.isHolding else { return }
        if let started = holdStartedAt {
            heldMs += UInt64(Date().timeIntervalSince(started) * 1000)
        }
        holdStartedAt = nil
        resumeRecording()
    }

    func resumeRecording() {
        guard recordingState.isPaused || recordingState.isHolding else { return }
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
            lastError = "Nothing was recorded."
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
        // Capture the hold before the background task starts; the property is
        // main-actor state and the recording is over by the time we are here.
        let held = heldMs

        Task.detached {
            do {
                let result = try KlinoteCore.note(
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
                // This practice's own vocabulary, learned from corrections the
                // clinician accepted. Applied before drafting, and announced.
                var (transcript, learned) = LearnedTerms.apply(to: result.transcript)
                // Say that the gap was deliberate. Silence in a consult is
                // ambiguous; a held stretch is a decision.
                transcript.heldMs = held
                let fallback = learned > 0
                    ? (try? KlinoteCore.note(fromTranscript: transcript, templateId: templateId)) ?? result.note
                    : result.note
                let note = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: fallback
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
                        transcript: transcript,
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
                    self.syncTasks(for: encounter)
                    RecordingStripController.shared.hide()
                    self.workspace = .letter
                    ReviewWindowController.shared.show()
                    if learned > 0 {
                        self.copyBanner = learned == 1
                            ? "1 learned correction applied."
                            : "\(learned) learned corrections applied."
                    } else {
                        self.promptPasteIfReady()
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.pendingRecording = nil
                    self.lastError = "Could not write this note. Record again if you still need it."
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

    /// Copy, but only without asking when the consult being copied is the one
    /// on screen. The failure this prevents is pasting the wrong patient's note
    /// at 11:40 with a queue outside, and it is the cheapest harm to avoid.
    /// Copy and print differ only in what they do at the end and which sheet
    /// they raise, so they share one path through the guard. Two copies of
    /// this logic is how the print guard came to be missing for a while.
    enum Output { case copy, print }

    func requestCopy(of encounterID: String) {
        request(.copy, of: encounterID)
    }

    func request(_ output: Output, of encounterID: String) {
        guard let encounter = encounters.first(where: { $0.id == encounterID }) else { return }
        switch CopyGuard.decision(
            requested: encounterID,
            selection: selection,
            isOnScreen: ReviewWindowController.shared.isShowing,
            hasNote: encounter.note != nil
        ) {
        case .nothingToCopy:
            return
        case .allowed:
            act(output)
        case .confirm:
            selection = encounterID
            selectedSentenceID = nil
            selectFirstEvidence()
            ReviewWindowController.shared.show()
            switch output {
            case .copy: pendingCopy = encounter
            case .print: pendingPrint = encounter
            }
        }
    }

    private func act(_ output: Output) {
        switch output {
        case .copy: copySelectedNote()
        case .print: printSelectedNote()
        }
    }

    /// Puts paste-ready plain text on the clipboard. Section titles and bodies
    /// only: no Markdown, no engine name, no unfiled statements, no footer.
    func copySelectedNote() {
        guard let note = selectedEncounter?.note else { return }
        do {
            let text = try KlinoteCore.recordText(for: note)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lastError = "Nothing to copy yet — this note has no documented sections."
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            isCopying = true
            // Name the consult in the receipt, so a paste can be checked
            // against what the clipboard actually holds.
            if let encounter = selectedEncounter {
                copyBanner = "On the clipboard. Paste it into the record you already use. Nothing left this Mac."
            } else {
                copyBanner = "On the clipboard. Paste it into the record you already use. Nothing left this Mac."
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.isCopying = false
                if self.copyBanner?.hasPrefix("Copied") == true {
                    self.copyBanner = nil
                }
            }
        } catch {
            lastError = "Could not copy the note."
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
                let rules = try KlinoteCore.note(fromTranscript: transcript, templateId: templateId)
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
                    self.lastError = "Could not rebuild the note after swapping speakers."
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

    // MARK: - Rewriting a note the rules wrote

    /// Whether the note on screen was written without the model, and could be
    /// written again now that the model exists.
    ///
    /// This is the honest half of the fallback. The rules produce a real note
    /// from the transcript, so nothing breaks without Quire — but it is a
    /// thinner note, and it looked exactly like a model-written one, which is
    /// how a clinician ends up trusting a worse draft without knowing there was
    /// a choice.
    var selectedNoteIsRuleBased: Bool {
        guard let encounter = selectedEncounter,
              let note = encounter.note,
              encounter.transcript != nil
        else { return false }
        return note.wasWrittenByRules
    }

    /// Show it whenever the note on screen was written by the rules, whether or
    /// not Quire is installed.
    ///
    /// It first appeared only when Quire was missing, which had a hole in it: a
    /// pasted transcript is written by the rules even on a machine that has
    /// Quire, because the paste path never asked it. That note stayed thin with
    /// nothing offering to improve it. The prompt now covers both — download
    /// the model, or just use the one that is already here.
    var showsNoteModelPrompt: Bool {
        guard selectedNoteIsRuleBased else { return false }
        guard selectedEncounter?.isSyntheticDemo != true else { return false }
        return true
    }

    /// Which consult the clinician asked to have written again, if a download
    /// is on its way. Nil when nothing has been asked for.
    private var pendingRewriteID: String?

    /// The prompt's download button. Records the consult before the download
    /// starts, because by the time it finishes the selection may be somebody
    /// else entirely.
    func requestRewriteWithNoteModel() {
        pendingRewriteID = selectedEncounter?.id
        ModelDownloader.shared.startNote()
    }

    private func noteIsWrittenByRules(_ encounterID: String) -> Bool {
        encounters.first { $0.id == encounterID }?.note?.wasWrittenByRules ?? false
    }

    /// A model that can write a note is present, so the only thing missing is
    /// the writing.
    var noteModelReady: Bool {
        if case .ready = ModelDownloader.shared.noteState { return true }
        return false
    }

    /// Whether anything at all could write a better note than the rules: Quire
    /// on disk, or Apple's model on a Mac that has it.
    private var aModelCouldWriteThis: Bool {
        noteModelReady || NoteDrafter.isAvailable
    }

    /// Write the note again from the stored transcript, now that Quire is here.
    ///
    /// The recording is gone by the time the download finishes — audio is
    /// discarded as soon as it is transcribed — but the transcript is kept, and
    /// the transcript is all the model ever needed. So a model that arrives
    /// late upgrades the note that is already on screen instead of asking the
    /// clinician to record the consultation again.
    @discardableResult
    func redraftWithNoteModel(_ encounterID: String? = nil, announceFailure: Bool = false) async -> Bool {
        guard let id = encounterID ?? selection,
              let stored = encounters.first(where: { $0.id == id }),
              let transcript = stored.transcript,
              let existing = stored.note
        else { return false }
        // Same consult twice is pointless; a different consult is not.
        guard !redrafting.contains(id) else { return false }
        let template = templates.first { $0.id == stored.templateId } ?? templates.first
        guard let template else { return false }

        redrafting.insert(id)
        defer { redrafting.remove(id) }

        let drafted = await Self.preferLocalDraft(
            transcript: transcript,
            template: template,
            fallback: existing
        )
        // The model may still have failed; if the result is the note we already
        // had, say so by doing nothing rather than pretending it improved.
        guard !drafted.wasWrittenByRules else {
            if announceFailure {
                lastError = "Quire could not write this note. The draft is unchanged."
            }
            return false
        }
        // Anything the clinician typed is in no transcript, so the model cannot
        // have written it and replacing the note would delete it.
        let note = NoteEditing.carryingAuthoredLines(from: existing, into: drafted)

        var updated = stored
        updated.note = note
        if updated.state == .draft {
            updated.state = .edited
        }
        if let index = encounters.firstIndex(where: { $0.id == updated.id }) {
            encounters[index] = updated
        }
        persist(updated)
        syncTasks(for: updated)
        promptPasteIfReady()
        copyBanner = "Quire wrote this note again from the transcript."
        return true
    }

    func applyNameCheck(heard: String, suggest: String) {
        guard var encounter = selectedEncounter,
              var note = encounter.note,
              var transcript = encounter.transcript
        else { return }
        for index in transcript.segments.indices {
            transcript.segments[index].text = transcript.segments[index].text
                .replacingOccurrences(of: heard, with: suggest, options: .caseInsensitive)
        }
        for index in note.sections.indices {
            note.sections[index].body = note.sections[index].body
                .replacingOccurrences(of: heard, with: suggest, options: .caseInsensitive)
            for sentence in note.sections[index].sentences.indices {
                note.sections[index].sentences[sentence].text = note.sections[index].sentences[sentence].text
                    .replacingOccurrences(of: heard, with: suggest, options: .caseInsensitive)
            }
        }
        transcript.nameChecks?.removeAll {
            $0.heard.compare(heard, options: .caseInsensitive) == .orderedSame
        }
        encounter.transcript = transcript
        encounter.note = note
        encounter.state = .edited
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        // Accepting a suggestion teaches this practice's vocabulary.
        LearnedTerms.learn(heard: heard, replacement: suggest)
        promptPasteIfReady()
    }

    /// Correct one sentence of the note.
    ///
    /// This is the step the product promises and did not have: the clinician
    /// reviews, **corrects**, then signs. An edited sentence is the clinician's
    /// own words, so the machine's grounding and wording flags come off it —
    /// they judge model claims, not a human's.
    ///
    /// It does not teach the vocabulary. Learning stays tied to an explicit
    /// acceptance, so a typo never becomes a rule.
    /// Write a line into a section the engine left empty, or short.
    ///
    /// The line is marked as a person's, so nothing downstream can present it
    /// as something the patient said, and the note stops being a pure machine
    /// draft the moment one is added.
    @discardableResult
    func addSentence(toSection key: String, text: String) -> Bool {
        guard var encounter = selectedEncounter, let note = encounter.note else { return false }
        guard let updated = NoteEditing.adding(
            text,
            toSection: key,
            in: note,
            lineId: UUID().uuidString
        ) else { return false }

        encounter.note = updated
        if encounter.state == .draft {
            encounter.state = .edited
        }
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
        return true
    }

    func commitSentenceEdit(_ sentenceID: String, to newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { editingSentenceID = nil }
        guard !trimmed.isEmpty else { return }
        guard var encounter = selectedEncounter, var note = encounter.note else { return }

        var changed = false
        for sectionIndex in note.sections.indices {
            for sentenceIndex in note.sections[sectionIndex].sentences.indices {
                guard note.sections[sectionIndex].sentences[sentenceIndex].id == sentenceID else {
                    continue
                }
                guard note.sections[sectionIndex].sentences[sentenceIndex].text != trimmed else {
                    return
                }
                note.sections[sectionIndex].sentences[sentenceIndex].text = trimmed
                note.sections[sectionIndex].sentences[sentenceIndex].support = "supported"
                note.sections[sectionIndex].sentences[sentenceIndex].wording = "plain"
                note.sections[sectionIndex].body = note.sections[sectionIndex]
                    .sentences
                    .map(\.text)
                    .joined(separator: " ")
                changed = true
            }
        }
        guard changed else { return }

        encounter.note = note
        if encounter.state == .draft {
            encounter.state = .edited
        }
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        promptPasteIfReady()
    }

    // MARK: - Derived

    var menuBarSymbol: String {
        if recordingState.isRecording { return "waveform.circle.fill" }
        if recordingState.isPaused { return "pause.circle" }
        return "waveform.circle"
    }

    var nameCheckCount: Int {
        selectedEncounter?.transcript?.nameChecks?.count ?? 0
    }

    /// Shorthand the patient would have to decode. Only ever set on a
    /// patient-facing document.
    func jargonCount(for note: ClinicalNote) -> Int {
        note.sections.flatMap(\.sentences).filter(\.isJargon).count
    }

    /// What the letterhead says, from the one implementation of the rule.
    func readiness(for encounter: Encounter) -> Readiness {
        guard let note = encounter.note else { return .empty }
        return Readiness.of(
            missingRequired: note.missingRequired,
            nameChecks: encounter.transcript?.nameChecks?.count ?? 0,
            jargon: jargonCount(for: note),
            unfiled: note.unassigned.count
        )
    }

    /// Ready to paste: required sections filled, no unresolved name checks.
    var isPasteReady: Bool {
        selectedEncounter.map(readiness(for:))?.isPasteReady ?? false
    }

    func promptPasteIfReady() {
        guard let encounter = selectedEncounter else { return }
        switch readiness(for: encounter) {
        case .namesToCheck(let count):
            copyBanner = count == 1
                ? "Check the drug name, then copy."
                : "Check \(count) names, then copy."
        case .ready, .empty:
            copyBanner = "Ready. Copy the note into the record."
        case .missingRequired, .wording:
            break
        }
    }

    var completenessLine: String {
        guard let encounter = selectedEncounter, let note = encounter.note else { return "" }
        let filled = note.sections.filter {
            !$0.body.trimmingCharacters(in: .whitespaces).isEmpty
        }.count
        return Readiness.completenessLine(
            sections: note.sections.count,
            filled: filled,
            missingTitles: note.missingRequired.map { key in
                note.sections.first { $0.key == key }?.title ?? key
            },
            readiness: readiness(for: encounter)
        )
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
    static let review = "klinote.review"
}
