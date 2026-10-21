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
    @Published var selectedSentenceID: String? {
        didSet {
            // One selection at a time. Choosing a note sentence leaves the
            // unfiled-statement source view; otherwise the margin would keep
            // answering the old question.
            if selectedSentenceID != nil { selectedUnfiledID = nil }
        }
    }
    /// The unfiled statement whose source is being read, when one is. The
    /// margin answers for it the same way it answers for a sentence: the
    /// words that were said, opened by the clinician's own "show source".
    @Published var selectedUnfiledID: String?

    /// Which stage of the capture pipeline is running, when one is. Real
    /// stages only: the recogniser reports no percentage, so the strip names
    /// the step and shows elapsed time — a fabricated bar would claim
    /// progress nobody can measure.
    enum ProcessingStage: Equatable { case transcribing, writing }
    @Published var processingStage: ProcessingStage?
    @Published var discipline = "psychology"
    @Published var templateId = "psychology"
    @Published var lastError: String?
    @Published var isFiling = false
    /// Whether the newest mutation of a session reached the encrypted store,
    /// keyed by encounter id. Set on every save attempt; read by the
    /// letterhead. A screen that says nothing while the store said no is a
    /// success lie — the exact failure this exists to prevent.
    @Published private(set) var saveOutcomes: [String: SaveOutcome] = [:]
    /// Encounter ids with a mutation that never persisted. They stay visible
    /// and retryable; nothing here deletes the clinician's copy.
    @Published private(set) var unsavedEncounterIDs: Set<String> = []
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
    /// The section the refusal sheet asked to open. `SectionBlock` watches
    /// this and opens its editor on arrival; nil when nothing is asked.
    @Published var focusedSectionKey: String?

    /// The refusal sheet's jump: open the letter on the missing section and
    /// put its editor on screen. One click from "not ready" to doing the
    /// thing that makes it ready.
    func focusMissingSection(_ key: String) {
        focusedSectionKey = key
    }
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

    /// Retrying a save that failed. The clinician's in-memory copy is the only
    /// copy until this succeeds, so the retry reuses the exact revision on
    /// screen — never a rebuilt one.
    func retrySave(of encounterID: String) {
        guard let encounter = encounters.first(where: { $0.id == encounterID }) else { return }
        persist(encounter)
    }

    /// The checklist and the ticks, derived from one store read.
    @Published private(set) var board = TaskBoard()

    /// Every read and write of the encrypted store. AppModel does not know
    /// about paths, keys or the C ABI.
    private let store = SessionStore()
    /// Where failed captures wait for their retry. Opened once; retention is
    /// enforced at open and at every refresh.
    private lazy var vault = CaptureVault.open()
    /// Set when a copy is requested for a consult that is not on screen. The
    /// clinician confirms before the clipboard changes.
    @Published var pendingCopy: Encounter?
    /// Set when print is requested for a consult that is not on screen.
    @Published var pendingPrint: Encounter?

    /// When the current (or just-finished) recording started.
    private var recordingStart: Date?
    /// When the current hold began, if one running.
    private var holdStartedAt: Date?
    /// Total time deliberately not captured in the current recording.
    private var heldMs: UInt64 = 0
    /// Captures that failed after the microphone stopped. Kept encrypted on
    /// this Mac, offered on the desk with Retry or Discard. A capture the
    /// clinician cannot recover is a session they must re-live.
    @Published private(set) var recoveries: [RecoverableCapture] = []
    /// The recovery currently being retried, so the strip can say so.
    @Published private(set) var retryingRecoveryID: String?

    private var noteDownloadObserver: NSObjectProtocol?
    private var ticker: Timer?

    private init() {
        copiedReceipts = Self.loadReceipts()
        // When Quire arrives, rewrite the note on screen if the rules wrote
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

    /// Clipboard receipts, per encounter. The desk's "still on this Mac"
    /// reads this: an encounter with a current receipt has left; one whose
    /// receipt is stale — edited after the copy — is here again, and one
    /// never copied never left. Review and copy stay separate claims.
    @Published private(set) var copiedReceipts: [String: CopiedReceipt] = [:] {
        didSet { Self.saveReceipts(copiedReceipts) }
    }

    private static let copiedReceiptsKey = "klinote.copiedReceipts"

    private static func loadReceipts() -> [String: CopiedReceipt] {
        guard let data = UserDefaults.standard.data(forKey: copiedReceiptsKey),
              let receipts = try? JSONDecoder().decode([String: CopiedReceipt].self, from: data)
        else { return [:] }
        return receipts
    }

    private static func saveReceipts(_ receipts: [String: CopiedReceipt]) {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        UserDefaults.standard.set(data, forKey: copiedReceiptsKey)
    }

    /// Drafts that never made it into the record. The desk's only inbox.
    ///
    /// "Made it into the record" is unknowable — Klinote cannot see the
    /// record system — so this is honest about what it knows: whether the
    /// clipboard has provably carried this exact revision. An approval is
    /// a claim about reading, not about the clipboard, and no longer
    /// decides this list (that was the old rule, and it made reviewing a
    /// draft look like having dealt with it).
    var uncopied: [Encounter] {
        encounters.filter { encounter in
            guard !encounter.isSyntheticDemo, encounter.note != nil else { return false }
            guard let receipt = copiedReceipts[encounter.id] else { return true }
            return !receipt.isCurrent(for: encounter.note!)
        }
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
        // Failed captures come back with the app. Expiry runs here: a recovery
        // older than the policy is destroyed before it is ever offered.
        refreshRecoveries()
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
    /// Failure is reported, not swallowed: "deleted 0" and "could not reach
    /// the store" are different answers, and only one of them is safe to
    /// show as a receipt.
    @discardableResult
    func purgeExpiredNotes() -> Int {
        do {
            let removed = try store.purge(months: retentionMonths)
            if removed > 0 {
                copyBanner = removed == 1
                    ? "Deleted 1 note past the retention period."
                    : "Deleted \(removed) notes past the retention period."
            }
            return removed
        } catch {
            lastError = "Could not run retention. Nothing was deleted: \(error.localizedDescription)"
            return 0
        }
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
        // Paper cannot be recalled, so print holds the same line as copy.
        switch OutputPolicy.decision(for: readiness(for: encounter)) {
        case .blocked(let reason):
            pendingReviewRequest = PendingOutput(
                encounter: encounter,
                kind: .print,
                reason: reason
            )
            return
        case .allowed:
            break
        }
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
            let startingRevision = rules.generatedAt
            Task.detached {
                let drafted = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: fallback
                )
                await MainActor.run {
                    if let index = self.encounters.firstIndex(where: { $0.id == document.id }) {
                        // Same rule as a redraft: do not replace a revision the
                        // clinician changed while the model was working.
                        guard self.encounters[index].note?.generatedAt == startingRevision else {
                            self.lastError = "The document changed while it was being written again. Nothing was replaced."
                            return
                        }
                        // A line typed into the document while the model was
                        // working is in no transcript, so it has to be carried.
                        let current = self.encounters[index].note
                        self.encounters[index].note = current.map {
                            NoteEditing.carryingAuthoredLines(
                                from: $0,
                                into: drafted,
                                requiredKeys: self.requiredKeys(for: template)
                            )
                        } ?? drafted
                        self.markRedrafted(&self.encounters[index], note: self.encounters[index].note!)
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
        guard PatientReference.isOpaqueCode(trimmed) else {
            lastError = "Use an opaque code — letters, digits, dot, dash or underscore — not a name."
            return
        }
        guard let index = encounters.firstIndex(where: { $0.id == id }) else { return }
        encounters[index].patientRef = trimmed
        persist(encounters[index])
    }

    func deleteEncounter(_ id: String) {
        // The bundled sample was never recorded, so there is nothing in the
        // store to remove for it.
        let isBundledSample = encounters.contains { $0.id == id && $0.isSyntheticDemo }
        if !isBundledSample {
            do {
                try store.delete(encounterID: id)
            } catch {
                // Deletion failed, so the row is still on the disk. Removing
                // it from the screen would be a lie with worse consequences
                // than a visible failure: the clinician would believe content
                // gone that the next retention sweep or export would find.
                lastError = "Could not delete the session. It is still on this Mac: \(error.localizedDescription)"
                return
            }
        }
        encounters.removeAll { $0.id == id }
        saveOutcomes[id] = nil
        unsavedEncounterIDs.remove(id)
        copiedReceipts[id] = nil
        if selection == id {
            selection = encounters.first?.id
            selectedSentenceID = nil
            selectFirstEvidence()
        }
    }

    func persist(_ encounter: Encounter) {
        var toSave = encounter
        // Mint stable identities and normalise derived bodies before the
        // write. Doing it here — the one place every mutation passes — is
        // what makes legacy notes safe: the first save after this change
        // gives every engine line an id, so no later edit can orphan it.
        if let note = encounter.note {
            var rebuilt = note
            for sectionIndex in rebuilt.sections.indices {
                NoteEditing.rebuildSection(&rebuilt.sections[sectionIndex])
            }
            let normalized = NoteEditing.mintingLineIds(for: rebuilt)
            toSave.note = normalized

            // The minted ids only in `toSave` used to leave the on-screen note
            // with none, so the next save minted a different set and the first
            // edit changed the sentence's identity under the selection. Assign
            // the normalised revision back to the in-memory encounter, and
            // carry the selection to the same line.
            if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
                if let oldNote = encounter.note,
                   let selected = selectedSentenceID,
                   let location = Self.location(of: selected, in: oldNote),
                   location.section < normalized.sections.count,
                   location.sentence < normalized.sections[location.section].sentences.count
                {
                    selectedSentenceID = normalized.sections[location.section].sentences[location.sentence].id
                }
                encounters[index].note = normalized
            }
        }
        do {
            try store.save(toSave, clinician: clinicianName)
            saveOutcomes[toSave.id] = .saved
            unsavedEncounterIDs.remove(toSave.id)
        } catch {
            saveOutcomes[toSave.id] = .failed(error.localizedDescription)
            unsavedEncounterIDs.insert(toSave.id)
            lastError = "Could not save this session. It is on screen but not on this Mac: \(error.localizedDescription)"
        }
        // Keeps the derived lists in step with the consult list without
        // another store read: this is all in memory.
        rebuildTaskViews()
    }

    private static func location(
        of sentenceID: String,
        in note: ClinicalNote
    ) -> (section: Int, sentence: Int)? {
        for (sectionIndex, section) in note.sections.enumerated() {
            if let sentenceIndex = section.sentences.firstIndex(where: { $0.id == sentenceID }) {
                return (sectionIndex, sentenceIndex)
            }
        }
        return nil
    }

    // MARK: - Note edits: move, exclude, restore

    /// The template's required section keys for an encounter. The engine's
    /// `missing_required` list is only a draft-time snapshot; edits need the
    /// real flags to keep the completeness check honest after moves and
    /// exclusions. Also what `SectionBlock` reads to decide whether an empty
    /// section earns the "not discussed" affordance.
    func requiredKeys(for encounter: Encounter) -> Set<String> {
        guard let template = templates.first(where: { $0.id == encounter.templateId })
            ?? templates.first
        else { return [] }
        return requiredKeys(for: template)
    }

    private func requiredKeys(for template: TemplateSummary?) -> Set<String> {
        Set((template?.sections ?? []).filter(\.required).map(\.key))
    }

    /// Move a sentence into another section. Evidence and provenance travel
    /// with the line; completeness and missing-required are recomputed.
    func moveSentence(_ sentenceID: String, toSection key: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let updated = NoteEditing.moving(
            sentenceID: sentenceID, toSection: key, in: note,
            requiredKeys: requiredKeys(for: encounter)
        ) else { return }
        pushUndo(for: encounter, kind: .move)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
    }

    /// Exclude a sentence from the note. Reversible; the source and the
    /// decision both survive, and the clipboard skips the line.
    func excludeSentence(_ sentenceID: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let updated = NoteEditing.excluding(
            sentenceID: sentenceID, in: note,
            requiredKeys: requiredKeys(for: encounter)
        ) else { return }
        pushUndo(for: encounter, kind: .exclude)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
    }

    /// Bring back an excluded sentence.
    func restoreSentence(_ sentenceID: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let updated = NoteEditing.restoring(
            sentenceID: sentenceID, in: note,
            requiredKeys: requiredKeys(for: encounter)
        ) else { return }
        pushUndo(for: encounter, kind: .exclude)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
    }

    /// File an unfiled statement into a section. The margin keeps pointing
    /// at the words that were said — that is the whole reason the item
    /// carried evidence in the first place.
    func fileUnfiled(_ itemID: String, toSection key: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let item = note.unassigned.first(where: { $0.id == itemID }) else { return }
        guard var updated = NoteEditing.adding(
            item.text,
            toSection: key,
            in: note,
            lineId: UUID().uuidString
        ) else { return }
        guard let removeIndex = updated.unassigned.firstIndex(where: { $0.id == itemID }) else { return }
        updated.unassigned.remove(at: removeIndex)
        // A filed statement is placed by a person but quoted from the room;
        // it is not an authored line and must not present as one. The
        // evidence it carried stays with it.
        if let sectionIndex = updated.sections.firstIndex(where: { $0.key == key }) {
            // The line just appended is the last one; it gets the item's
            // evidence so the margin keeps pointing at the words that were
            // said, and it is NOT authored — it was quoted from the room and
            // placed by a person, which is a different thing from written by
            // a person.
            if var added = updated.sections[sectionIndex].sentences.last {
                added.evidence = item.evidence
                added.authored = nil
                updated.sections[sectionIndex].sentences[updated.sections[sectionIndex].sentences.count - 1] = added
            }
        }
        pushUndo(for: encounter, kind: .edit)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
    }

    /// Exclude an unfiled statement: it leaves the queue and the decision is
    /// remembered, so the next redraft cannot revive it.
    func excludeUnfiled(_ itemID: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let updated = NoteEditing.excludingUnfiled(itemID, from: note) else { return }
        pushUndo(for: encounter, kind: .exclude)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        promptPasteIfReady()
    }

    /// Put an excluded unfiled statement back into the queue.
    func restoreUnfiled(_ itemID: String) {
        guard var encounter = selectedEncounter, let note = encounter.note else { return }
        guard let updated = NoteEditing.restoringUnfiled(itemID, from: note) else { return }
        pushUndo(for: encounter, kind: .exclude)
        markEdited(&encounter, note: updated)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        promptPasteIfReady()
    }

    // MARK: - Tasks

    /// One row per sentence in a section the template marks as work to do.
    ///
    /// Called after a note is drafted or edited. It reconciles rather than only
    /// appends: a sentence that was corrected, moved out of an action section,
    /// or excluded used to leave its old task open forever. A task the
    /// clinician has ticked is never deleted — that is a record of work done,
    /// not a derived row.
    func syncTasks(for encounter: Encounter) {
        guard let note = encounter.note else { return }
        let template = templates.first { $0.id == encounter.templateId }
        var wanted: [String: String] = [:]
        for section in note.sections {
            let isAction = template?
                .sections.first { $0.key == section.key }?
                .actions ?? false
            guard isAction else { continue }
            for sentence in section.sentences where sentence.isPresent {
                wanted[sentence.text] = section.key
            }
        }

        reloadTasks()
        let existing = board.all.filter { $0.encounterId == encounter.id }
        let existingTexts = Set(existing.map(\.text))
        for task in existing where !task.done && !wanted.keys.contains(task.text) {
            try? store.deleteTask(id: task.id)
        }
        for (text, key) in wanted where !existingTexts.contains(text) {
            try? store.addTask(encounterID: encounter.id, text: text, sourceKey: key)
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

    /// Show the source of an unfiled statement: the words that were said, in
    /// the margin, without pretending the statement is a note sentence.
    func showSource(of item: UnassignedStatement) {
        selectedSentenceID = nil
        selectedUnfiledID = item.id
    }

    /// The unfiled statement whose source is showing, if any.
    var selectedUnfiledItem: UnassignedStatement? {
        guard let id = selectedUnfiledID else { return nil }
        return selectedEncounter?.note?.unassigned.first { $0.id == id }
    }

    /// Every sentence the note actually consists of, in reading order. This
    /// is what arrow-key movement steps through — a line excluded from the
    /// note is not part of the journey either.
    var presentSentenceIDs: [String] {
        guard let note = selectedEncounter?.note else { return [] }
        return note.sections.flatMap(\.sentences).filter(\.isPresent).map(\.id)
    }

    /// Move sentence selection by `offset` through the document, wrapping at
    /// the ends so an arrow key never feels stuck on the last line.
    func selectAdjacentSentence(_ offset: Int) {
        let ids = presentSentenceIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedSentenceID,
              let index = ids.firstIndex(of: current)
        else {
            selectedSentenceID = offset < 0 ? ids.last : ids.first
            return
        }
        selectedSentenceID = ids[(index + offset + ids.count) % ids.count]
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
                        // The model finishing is a machine redraft of the
                        // bundled sample: a revision no human has seen, so
                        // the review state resets rather than inheriting.
                        self.markRedrafted(&self.encounters[index], note: drafted)
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
        // Listening is not a download any more. It used to be: the app could not
        // transcribe until 465 MB of whisper.cpp model had arrived, so a
        // recording taken before then was held in `pendingRecording` and
        // transcribed when the download landed. `SpeechAnalyzer` is part of the
        // OS, so there is nothing to wait for and nothing to hold.
        guard Transcriber.isAvailable else {
            lastError = Transcriber.unavailableReason
                ?? "Transcribing is not available on this Mac."
            return
        }
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

        // Read before the recorder is reset: this is the honest "how much of
        // the session was captured", from the file, not the clock. This used
        // to run after `stop()`, which closes the file, so it was always nil.
        let capturedMs = Recorder.shared.capturedMilliseconds
        let url = Recorder.shared.capturedFile()
        Recorder.shared.stop()
        let startedAt = recordingStart ?? Date()
        recordingStart = nil

        guard let url else {
            RecordingStripController.shared.hide()
            recordingState = .idle
            processingStage = nil
            lastError = "Nothing was recorded."
            return
        }

        processingStage = .transcribing
        transcribe(url, startedAt: startedAt, capturedMs: capturedMs)
    }

    /// Recognise a captured recording, then file it.
    ///
    /// Off the main actor: recognition runs for as long as the consultation
    /// did, and nothing about it may hold the interface.
    ///
    /// `recoveryID` is set when this is a retry of a stored capture: the
    /// encounter keeps the original's identity and start time, so a retry
    /// files one session rather than minting a second one.
    private func transcribe(_ url: URL, startedAt: Date, capturedMs: UInt64? = nil, recoveryID: String? = nil) {
        let templateId = self.templateId
        let discipline = self.discipline
        let patientRef = recoveryID ?? nextPatientRef()
        // Capture the hold before the background task starts; the property is
        // main-actor state and the recording is over by the time we are here.
        let held = heldMs
        // This practice's own spellings, so a drug name it has already settled
        // on is less likely to be misheard in the first place.
        let vocabulary = LearnedTerms.vocabulary()

        Task.detached {
            do {
                // Recognition first, in Swift, because `SpeechAnalyzer` is a
                // Swift API. The words then cross to the Rust engine, which owns
                // diarisation, routing, grounding and completeness.
                let segments = try await Transcriber.transcribe(
                    file: url,
                    vocabulary: vocabulary
                )
                await self.draft(
                    segments: segments,
                    audio: url,
                    startedAt: startedAt,
                    held: held,
                    templateId: templateId,
                    discipline: discipline,
                    patientRef: patientRef,
                    recoveryID: recoveryID
                )
            } catch {
                // The recording is the one thing the clinician cannot re-live.
                // It is sealed, encrypted, into the vault and offered for
                // retry — deleting it here is what made a failed transcription
                // a lost session.
                let capture = RecoverableCapture(
                    id: recoveryID ?? patientRef,
                    patientRef: patientRef,
                    discipline: discipline,
                    templateId: templateId,
                    startedAt: startedAt,
                    heldMs: held,
                    capturedMs: capturedMs,
                    stage: .captured,
                    failure: error.localizedDescription
                )
                let vaultError = await self.sealIntoVault(
                    audio: url,
                    capture: capture,
                    segments: nil
                )
                await MainActor.run {
                    // Name the stage: recognition and the engine fail for
                    // different reasons, and "could not write this note" sent
                    // whoever read it looking in the wrong place.
                    let stage = (error is TranscriberError) ? "hear" : "write"
                    let saved = vaultError.isEmpty
                    if stage == "hear" {
                        self.lastError = saved
                            ? "Could not make out that recording. It is saved encrypted on this Mac for 24 hours — Retry from the desk."
                            : "Could not make out that recording, and it could not be saved.\(vaultError) Record again if you still need it."
                    } else {
                        self.lastError = saved
                            ? "Could not write this note. The recording is saved encrypted on this Mac for 24 hours — Retry from the desk."
                            : "Could not write this note, and the recording could not be saved.\(vaultError) Record again if you still need it."
                    }
                    self.recordingState = .idle
                    self.elapsed = 0
                    self.processingStage = nil
                    self.retryingRecoveryID = nil
                    RecordingStripController.shared.hide()
                }
            }
        }
    }

    /// Draft and file a note from recognised segments. The second half of
    /// the capture pipeline, split out so a retry can start here without
    /// re-running recognition.
    private func draft(
        segments: [RecognisedSegment],
        audio: URL,
        startedAt: Date,
        held: UInt64,
        templateId: String,
        discipline: String,
        patientRef: String,
        recoveryID: String? = nil
    ) async {
        await MainActor.run { self.processingStage = .writing }
        do {
            let result = try KlinoteCore.note(
                fromSegments: segments,
                // The recording goes back so the engine can measure where the
                // silences are: the recogniser's ranges are contiguous, so
                // the turn boundaries are not in the timings. Deleted after,
                // not before.
                audioPath: audio,
                language: "en",
                engine: Transcriber.engineName,
                templateId: templateId,
                discipline: discipline,
                patientRef: patientRef
            )
            let template = await MainActor.run {
                self.templates.first(where: { $0.id == templateId }) ?? self.templates.first
            }
            // Vocabulary corrections the clinician accepted previously.
            // Applied before drafting, and announced.
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
            try? FileManager.default.removeItem(at: audio)
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
                self.lastError = nil
                self.recordingState = .idle
                self.elapsed = 0
                self.processingStage = nil
                self.persist(encounter)
                self.selectFirstEvidence()
                self.syncTasks(for: encounter)
                RecordingStripController.shared.hide()
                self.workspace = .letter
                ReviewWindowController.shared.show()
                if let recoveryID {
                    // The retry succeeded; the vault has served its purpose.
                    // A failed removal is reported rather than shown as gone.
                    if self.vault.destroy(id: recoveryID) {
                        self.recoveries.removeAll { $0.id == recoveryID }
                    } else {
                        self.lastError = "The note was saved, but the saved recording could not be removed from this Mac."
                    }
                    self.retryingRecoveryID = nil
                }
                if learned > 0 {
                    self.copyBanner = learned == 1
                        ? "1 learned correction applied."
                        : "\(learned) learned corrections applied."
                } else {
                    self.promptPasteIfReady()
                }
            }
        } catch {
            // The words were recognised but the draft failed. Both the audio
            // and the segments are sealed: a retry resumes at drafting and
            // never asks the clinician to record the session again.
            let capture = RecoverableCapture(
                id: recoveryID ?? patientRef,
                patientRef: patientRef,
                discipline: discipline,
                templateId: templateId,
                startedAt: startedAt,
                heldMs: held,
                capturedMs: segments.map(\.endMs).max(),
                stage: .recognised,
                failure: error.localizedDescription
            )
            let vaultError = await sealIntoVault(
                audio: audio,
                capture: capture,
                segments: segments
            )
            await MainActor.run {
                self.lastError = vaultError.isEmpty
                    ? "Could not write this note. The words and the recording are saved encrypted on this Mac for 24 hours — Retry from the desk."
                    : "Could not write this note, and the words could not be saved.\(vaultError) Record again if you still need it."
                self.recordingState = .idle
                self.elapsed = 0
                self.processingStage = nil
                self.retryingRecoveryID = nil
                RecordingStripController.shared.hide()
            }
        }
    }

    /// Seal a failed capture into the vault and refresh the visible list.
    /// Returns a sentence for the error message, or an empty string when the
    /// vault took the capture cleanly.
    private func sealIntoVault(
        audio: URL,
        capture: RecoverableCapture,
        segments: [RecognisedSegment]?
    ) async -> String {
        do {
            // Sealing reads and encrypts the whole recording; keep that off the
            // main actor. The vault is a value with its own Keychain key.
            let vault = self.vault
            try await Task.detached {
                try vault.seal(id: capture.id, audio: audio, capture: capture, segments: segments)
            }.value
            // The seal is now the only copy that matters; the plaintext temp
            // file has no reason to outlive it.
            try? FileManager.default.removeItem(at: audio)
            await MainActor.run {
                self.refreshRecoveries()
            }
            return ""
        } catch {
            // The plaintext temp file is the one thing the vault was meant to
            // replace. If sealing failed, it must not be left in $TMPDIR.
            try? FileManager.default.removeItem(at: audio)
            return " The recording could not be saved for retry."
        }
    }

    /// The recoveries the desk shows. Expiry is enforced here too, so a
    /// launch-day list never offers a recovery the vault has just removed.
    func refreshRecoveries() {
        let removed = vault.enforceRetention()
        recoveries = vault.list()
        if removed > 0, copyBanner == nil {
            copyBanner = removed == 1
                ? "Removed 1 saved capture past its 24-hour recovery window."
                : "Removed \(removed) saved captures past their 24-hour recovery window."
        }
    }

    /// Retry a stored capture from where it failed. A recognition retry asks
    /// the microphone's work of the saved audio; a drafting retry starts at
    /// the words — the session is never re-recorded for either.
    ///
    /// The capture's own discipline, template and patient ref are reused, not
    /// today's settings: a therapist who switched template after the failure
    /// still gets their session filed as it was recorded.
    func retryRecovery(_ id: String) {
        guard recordingState.isIdle, retryingRecoveryID == nil else { return }
        guard let capture = vault.capture(id: id) else {
            refreshRecoveries()
            return
        }
        var temporaryURL: URL?
        do {
            let audioData = try vault.unsealAudio(id: id)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("klinote-retry-\(id).wav")
            try audioData.write(to: url, options: .atomic)
            temporaryURL = url
            retryingRecoveryID = id
            recordingState = .finalising
            switch capture.stage {
            case .captured:
                transcribe(
                    url,
                    startedAt: capture.startedAt,
                    capturedMs: capture.capturedMs,
                    recoveryID: id
                )
            case .recognised:
                let (_, segments) = try vault.openSegments(id: id)
                Task.detached {
                    await self.draft(
                        segments: segments,
                        audio: url,
                        startedAt: capture.startedAt,
                        held: capture.heldMs,
                        templateId: capture.templateId,
                        discipline: capture.discipline,
                        patientRef: capture.patientRef,
                        recoveryID: id
                    )
                }
            }
        } catch {
            // Fail closed: an unopenable vault file is an error, never a
            // half-decrypted recording presented as the session. Reset the
            // retry state too, or one corrupt file disables every future retry
            // and leaves the strip claiming it is still writing.
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            retryingRecoveryID = nil
            recordingState = .idle
            processingStage = nil
            RecordingStripController.shared.hide()
            lastError = "Could not open that saved recording: \(error.localizedDescription)"
        }
    }

    /// The clinician chose to let a failed capture go. Everything the vault
    /// kept — audio, segments, metadata — is destroyed.
    func discardRecovery(_ id: String) {
        if vault.destroy(id: id) {
            recoveries.removeAll { $0.id == id }
        } else {
            lastError = "Could not remove that saved recording from this Mac."
            refreshRecoveries()
        }
    }

    /// Review is the clinician's claim: "I have read this revision and stand
    /// behind it." The machine never reaches here on its own, and neither
    /// does a note that still has something unresolved — an approval of an
    /// incomplete note would be a signature over a gap, which is worse than
    /// the gap.
    ///
    /// A blocked review names the fix and does not move the state. Reviewing
    /// does not touch the clipboard receipt: copied and reviewed stay two
    /// separate facts about two separate events.
    func fileSelectedNote() {
        guard var encounter = selectedEncounter, var note = encounter.note else { return }
        guard encounter.state != .approved else { return }
        switch OutputPolicy.decision(for: readiness(for: encounter)) {
        case .blocked(let reason):
            pendingReviewRequest = PendingOutput(
                encounter: encounter,
                kind: .review,
                reason: reason
            )
            return
        case .allowed:
            break
        }
        isFiling = true
        // Approval is a claim about this revision. The stored JSON is what a
        // relaunch reads, so the review state moves on the note itself — when
        // this only moved the shell's own state, the approved note reopened
        // as a draft and the clinician's act was quietly gone.
        note.reviewState = "approved"
        encounter.note = note
        encounter.state = .approved
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        isFiling = false
        // A save that failed leaves the approval unpublished: the encounter
        // keeps its in-memory state, the letterhead says not saved, and the
        // relaunch will read the last durable revision.
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
            // The core's grounding check, which this path does not otherwise get:
            // `NoteDrafter` assembles the note in Swift, so nothing has marked
            // its sentences. Every Rust drafting path is checked this way.
            //
            // If the check cannot run, the draft still beats the rules — but it
            // goes back unmarked, which is a real caveat and not worth being
            // quiet about.
            do {
                let verified = try KlinoteCore.verify(note: drafted, against: transcript)
                if template.audience == "patient" {
                    // Asking the model for plain language is not a guarantee.
                    // Enforce it with the same core transformer the Rust
                    // pipeline uses, or a patient summary can carry "q8h"
                    // while claiming it was checked.
                    return (try? KlinoteCore.simplifyForPatient(note: verified)) ?? verified
                }
                return verified
            } catch {
                NSLog(
                    "Klinote: could not ground the on-device draft, leaving it unmarked: %@",
                    error.localizedDescription
                )
                return drafted
            }
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

    /// A refused output: which note, which action, and the named reason.
    /// The sheet's buttons take the clinician to the fix rather than
    /// leaving them with a dead end.
    struct PendingOutput: Identifiable {
        enum Kind { case copy, print, review }
        let encounter: Encounter
        let kind: Kind
        let reason: String
        var id: String { encounter.id + String(describing: kind) }
    }
    @Published var pendingReviewRequest: PendingOutput?

    func requestCopy(of encounterID: String) {
        request(.copy, of: encounterID)
    }

    func request(_ output: Output, of encounterID: String) {
        guard let encounter = encounters.first(where: { $0.id == encounterID }) else { return }
        // The output policy runs on every route, before the wrong-session
        // guard: a hotkey or a menu item is not a way past an incomplete
        // note. The refusal names the fix and offers the jump.
        switch OutputPolicy.decision(for: readiness(for: encounter)) {
        case .blocked(let reason):
            pendingReviewRequest = PendingOutput(
                encounter: encounter,
                kind: output == .print ? .print : .copy,
                reason: reason
            )
            return
        case .allowed:
            break
        }
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
    ///
    /// The direct path — the toolbar, the signature block, the desk, the
    /// menus — checks the output policy here, in the one function every
    /// route reaches. A refused copy says what to fix and stays off the
    /// clipboard: a status code is not proof, but a refusal is at least a
    /// truth, and the alternative was a clinician pasting an incomplete
    /// note believing the app had their back.
    func copySelectedNote() {
        guard let encounter = selectedEncounter, let note = encounter.note else { return }
        switch OutputPolicy.decision(for: readiness(for: encounter)) {
        case .blocked(let reason):
            pendingReviewRequest = PendingOutput(
                encounter: encounter,
                kind: .copy,
                reason: reason
            )
            return
        case .allowed:
            break
        }
        do {
            let text = try KlinoteCore.recordText(for: note)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lastError = "Nothing to copy yet — this note has no documented sections."
                return
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                lastError = "Could not write to the clipboard."
                return
            }
            isCopying = true
            // The receipt is the difference between "this left" and "I think
            // this left". It is written only after a clipboard write that
            // returned true; this used to ignore the Bool and record a receipt
            // for a write that never happened.
            copiedReceipts[encounter.id] = CopiedReceipt(encounterID: encounter.id, note: note)
            copyBanner = "Copied. Paste it into the record you already use. Nothing left this Mac."
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.isCopying = false
            }
        } catch {
            lastError = "Could not copy the note."
        }
    }

    /// Swap clinician and patient, then rebuild the note. Keyboard: ⌥⌘S.
    ///
    /// A rebuild replaces the prose, so it must carry the clinician's own work
    /// across — corrections, added lines and excluded sentences — and it must
    /// not overwrite an edit made while the model was working.
    func swapSpeakersAndRedraft() {
        guard var encounter = selectedEncounter,
              var transcript = encounter.transcript,
              let existing = encounter.note
        else { return }
        guard !encounter.isSyntheticDemo else { return }
        isSwapping = true
        let startingRevision = existing.generatedAt
        transcript.swapClinicianAndPatient()
        let templateId = encounter.templateId
        let template = templates.first(where: { $0.id == templateId }) ?? templates.first
        Task.detached {
            do {
                let rules = try KlinoteCore.note(fromTranscript: transcript, templateId: templateId)
                let drafted = await Self.preferLocalDraft(
                    transcript: transcript,
                    template: template,
                    fallback: rules
                )
                await MainActor.run {
                    defer { self.isSwapping = false }
                    guard let index = self.encounters.firstIndex(where: { $0.id == encounter.id })
                    else { return }
                    // Do not replace a revision the clinician changed while
                    // the model was working. The swap can be retried; an edit
                    // cannot be recovered from a silent overwrite.
                    guard self.encounters[index].note?.generatedAt == startingRevision else {
                        self.lastError = "The note changed while the voices were being swapped. Nothing was replaced."
                        return
                    }
                    let note = NoteEditing.carryingAuthoredLines(
                        from: existing,
                        into: drafted,
                        requiredKeys: self.requiredKeys(for: template)
                    )
                    encounter.note = note
                    encounter.transcript = transcript
                    self.markRedrafted(&encounter, note: note)
                    self.encounters[index] = encounter
                    self.persist(encounter)
                    self.selectFirstEvidence()
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
        // A late result must not overwrite an edit made while the model was
        // running. Human edits restamp `generatedAt`; if it moved, the draft
        // is stale and the clinician's revision wins.
        guard let current = encounters.first(where: { $0.id == id }),
              let currentNote = current.note,
              currentNote.generatedAt == existing.generatedAt
        else {
            if announceFailure {
                lastError = "This note changed while it was being written again. Nothing was replaced."
            }
            return false
        }
        // Anything the clinician typed is in no transcript, so the model cannot
        // have written it and replacing the note would delete it.
        let note = NoteEditing.carryingAuthoredLines(
            from: currentNote,
            into: drafted,
            requiredKeys: requiredKeys(for: template)
        )

        var updated = current
        markRedrafted(&updated, note: note)
        if let index = encounters.firstIndex(where: { $0.id == updated.id }) {
            encounters[index] = updated
        }
        persist(updated)
        syncTasks(for: updated)
        promptPasteIfReady()
        let writer = drafted.engine.contains("apple-foundation") ? "Apple's on-device model" : "Quire"
        copyBanner = "\(writer) wrote this note again from the transcript."
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
        markEdited(&encounter, note: note)
        if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        // Accepting a suggestion teaches this practice's vocabulary.
        LearnedTerms.learn(heard: heard, replacement: suggest)
        promptPasteIfReady()
    }

    /// Apply the human-edit review rule to a note being changed, and keep the
    /// shell's state word in step with the stored one.
    ///
    /// One function because four call sites used to do this by hand and two
    /// of them (sentence edit, name check) forgot the review state entirely:
    /// a clinician could approve a note, correct a sentence, and reopen a
    /// note still marked reviewed — with the correction missing from the
    /// disk. Machine redrafts do not come through here; they go through
    /// `markRedrafted`, because a machine rewrite is a different claim.
    ///
    /// The revision is also restamped. `generated_at` is the engine's draft
    /// timestamp, and without this an edit leaves it untouched — which made
    /// a copied-then-edited note look like the same revision the clipboard
    /// receipt described. The restamp is what makes a receipt go stale the
    /// moment the words change, which is the whole property a receipt needs.
    private func markEdited(_ encounter: inout Encounter, note: ClinicalNote) {
        var revised = note
        revised.reviewState = ReviewDecision.stateAfterHumanEdit(
            current: note.reviewState
        )
        revised.generatedAt = Self.revisionStamp()
        // A human edit ends the claim that this is a machine-written revision.
        revised.machineGenerated = false
        encounter.note = revised
        encounter.state = NoteState(rawValue: revised.reviewState) ?? .edited
    }

    /// One revision stamp, one format. ISO-8601 like the engine writes it,
    /// so the stored JSON stays homogeneous.
    static func revisionStamp(now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now)
    }

    // MARK: - Undo

    /// One undoable step: the note as it was before an edit, and which kind
    /// of edit it was. Per-encounter, newest first, capped — a note is a
    /// document, not an infinite tape. Undo restores content only; the
    /// append-only audit log is never rewritten, and undo never re-approves.
    struct UndoStep {
        let note: ClinicalNote
        let kind: Kind

        enum Kind { case edit, move, exclude }
    }

    private var undoStacks: [String: [UndoStep]] = [:]
    private static let undoLimit = 20

    @Published private(set) var canUndoEncounterID: String?

    private func pushUndo(for encounter: Encounter, kind: UndoStep.Kind) {
        guard let note = encounter.note else { return }
        var stack = undoStacks[encounter.id] ?? []
        stack.append(UndoStep(note: note, kind: kind))
        if stack.count > Self.undoLimit { stack.removeFirst() }
        undoStacks[encounter.id] = stack
        canUndoEncounterID = encounter.id
    }

    /// Undo the newest note edit on the selected encounter. The restored
    /// revision is a human action on a document, so it keeps the review
    /// state the restored note had — which by construction is not "approved
    /// with the new edits", because approval of a since-edited revision was
    /// already invalidated when the edit landed.
    func undoLastEdit() {
        guard let id = selectedEncounter?.id,
              var stack = undoStacks[id], let step = stack.popLast()
        else { return }
        undoStacks[id] = stack
        canUndoEncounterID = stack.isEmpty ? nil : id
        guard var encounter = selectedEncounter else { return }
        var restored = step.note
        restored.reviewState = ReviewDecision.stateAfterUndo(restored: step.note.reviewState)
        encounter.note = restored
        encounter.state = NoteState(rawValue: restored.reviewState) ?? .edited
        if let index = encounters.firstIndex(where: { $0.id == id }) {
            encounters[index] = encounter
        }
        persist(encounter)
        syncTasks(for: encounter)
        promptPasteIfReady()
    }

    /// Apply the machine-redraft review rule: the new revision is one no
    /// human has seen, whatever the old one was. Applied to the Quire
    /// redraft, the voice swap and the download-completion rewrite — the
    /// paths that replace prose without a person in the loop.
    private func markRedrafted(_ encounter: inout Encounter, note: ClinicalNote) {
        var revised = note
        revised.reviewState = ReviewDecision.stateAfterMachineRedraft()
        encounter.note = revised
        encounter.state = .draft
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
        markEdited(&encounter, note: updated)
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
                // Provenance: the person rewrote this line. It is no longer
                // the engine's sentence, and the margin must say so — this
                // used to clear the machine's flags while leaving the line
                // looking machine-written, which is a fact nobody could see.
                note.sections[sectionIndex].sentences[sentenceIndex].authored = LineAuthorship.clinicianEdited
                // A stable id survives the text change, so selection and the
                // margin keep following the line they were following.
                if note.sections[sectionIndex].sentences[sentenceIndex].lineId == nil {
                    note.sections[sectionIndex].sentences[sentenceIndex].lineId = UUID().uuidString
                }
                if selectedSentenceID == sentenceID,
                   let minted = note.sections[sectionIndex].sentences[sentenceIndex].lineId {
                    // The sentence's identity just became stable. Follow it,
                    // or the margin clears itself the moment the edit saves.
                    selectedSentenceID = minted
                }
                // A human correction *clears* the machine's verdict; it does not
                // replace it with a pass. "supported" means "we checked this
                // against the words heard and its figures and drug names were
                // there", and re-typing the line did not re-run that check — so
                // writing it here would store a claim that never happened, in the
                // record, about the one sentence nobody had caught. `nil` is also
                // what a clinician-authored line carries when it is appended
                // (`NoteEditing`), so the two ways a sentence becomes the
                // clinician's own now agree.
                note.sections[sectionIndex].sentences[sentenceIndex].support = nil
                note.sections[sectionIndex].sentences[sentenceIndex].wording = "plain"
                changed = true
            }
        }
        guard changed else { return }

        pushUndo(for: encounter, kind: .edit)
        for sectionIndex in note.sections.indices {
            NoteEditing.rebuildSection(&note.sections[sectionIndex])
        }
        markEdited(&encounter, note: note)
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
