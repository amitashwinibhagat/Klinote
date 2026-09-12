//
// Decisions.swift
//
// The judgements the shell makes about a consult, as pure functions.
//
// Every one of these was a method on AppModel reading @Published state and, in
// two cases, reaching the encrypted store from inside a view body. As free
// functions over their inputs they are testable without an app, a database or
// a Keychain, and the compiler now stops a view from doing anything but ask.
//

import Foundation

// MARK: - Readiness

/// What the letterhead says about a note, and whether Copy note is the next
/// thing to do. The order matters: a name to check outranks a missing section,
/// because a wrong drug is worse than a missing paragraph.
enum Readiness: Equatable {
    case namesToCheck(Int)
    case missingRequired
    case wording
    case ready(unfiled: Int)
    case empty

    /// The short form for the letterhead's Status field.
    var label: String {
        switch self {
        case .namesToCheck(1): "1 name to check"
        case .namesToCheck(let count): "\(count) names to check"
        case .missingRequired: "Missing required"
        case .wording: "Check wording"
        case .ready(0): "Ready to copy"
        case .ready(let unfiled): "Ready · \(unfiled) not filed"
        case .empty: "No note"
        }
    }

    /// Whether the clipboard is one action away.
    var isPasteReady: Bool {
        switch self {
        case .ready, .empty: true
        case .namesToCheck, .missingRequired, .wording: false
        }
    }

    /// The sentence under the letterhead: counts, not scolding. A missing
    /// section is named, because "missing something required" makes the
    /// clinician go looking.
    static func completenessLine(
        sections: Int,
        filled: Int,
        missingTitles: [String],
        readiness: Readiness
    ) -> String {
        if !missingTitles.isEmpty {
            return "\(filled) of \(sections) sections · missing: \(missingTitles.joined(separator: ", "))"
        }
        switch readiness {
        case .namesToCheck(let count):
            return "\(filled) of \(sections) sections · \(count) name\(count == 1 ? "" : "s") to check"
        default:
            return "\(filled) of \(sections) sections documented · ready to copy"
        }
    }

    static func of(
        missingRequired: [String],
        nameChecks: Int,
        jargon: Int,
        unfiled: Int
    ) -> Readiness {
        if nameChecks > 0 { return .namesToCheck(nameChecks) }
        if !missingRequired.isEmpty { return .missingRequired }
        if jargon > 0 { return .wording }
        return .ready(unfiled: unfiled)
    }
}

// MARK: - The copy guard

/// Whether copying or printing this consult needs confirming first.
///
/// The failure this exists to prevent is pasting the wrong patient's note.
/// Copying what is already on screen is safe — the letterhead is right there —
/// and anything else is not.
enum CopyGuard: Equatable {
    case allowed
    case confirm
    case nothingToCopy

    static func decision(
        requested: String,
        selection: String?,
        isOnScreen: Bool,
        hasNote: Bool
    ) -> CopyGuard {
        guard hasNote else { return .nothingToCopy }
        return (requested == selection && isOnScreen) ? .allowed : .confirm
    }
}

// MARK: - Tasks

/// The two views of the task list, both derived from one read.
enum TaskViews {
    /// Open tasks paired with their consult, for the still-to-do list.
    static func openRows(
        tasks: [ConsultTask],
        encounters: [Encounter]
    ) -> [(task: ConsultTask, encounter: Encounter)] {
        let byId = Dictionary(encounters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.compactMap { task in
            guard !task.done, let encounter = byId[task.encounterId] else { return nil }
            return (task, encounter)
        }
    }

    /// The selected consult's tasks keyed by the sentence they came from, so a
    /// view body can ask for a sentence's tick without touching the store.
    static func index(tasks: [ConsultTask], encounterID: String?) -> [String: ConsultTask] {
        guard let encounterID else { return [:] }
        return tasks
            .filter { $0.encounterId == encounterID }
            .reduce(into: [:]) { index, task in index[task.text] = task }
    }
}

// MARK: - Grouping

/// Consults grouped by the day they happened, newest first.
enum EncounterGrouping {
    struct Group {
        let day: String
        let encounters: [Encounter]
    }

    /// `clinician` scopes the list on a shared practice Mac. A consult saved
    /// before anyone said who they were has no clinician and is shown to
    /// everyone: hiding a note is worse than showing one that is not yours.
    static func groups(
        from encounters: [Encounter],
        matching query: String,
        today: Date,
        calendar: Calendar = .current,
        clinician: String? = nil,
        showAllClinicians: Bool = false
    ) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mine = clinician?.trimmingCharacters(in: .whitespacesAndNewlines)

        let scoped = (mine?.isEmpty ?? true) || showAllClinicians
            ? encounters
            : encounters.filter { $0.clinicianRef == nil || $0.clinicianRef == mine }

        let filtered = needle.isEmpty
            ? scoped
            : scoped.filter { matches($0, needle: needle) }

        var order: [Date] = []
        var byDay: [Date: [Encounter]] = [:]
        for encounter in filtered.sorted(by: { $0.startedAt > $1.startedAt }) {
            let day = calendar.startOfDay(for: encounter.startedAt)
            if byDay[day] == nil {
                byDay[day] = []
                order.append(day)
            }
            byDay[day]?.append(encounter)
        }
        return order.map { Group(day: dayLabel($0, today: today, calendar: calendar),
                                 encounters: byDay[$0] ?? []) }
    }

    /// Searches the code, the document name, the state, the note body and the
    /// words that were said. A clinician looking for a consult remembers any
    /// of those.
    static func matches(_ encounter: Encounter, needle: String) -> Bool {
        if encounter.patientRef.lowercased().contains(needle) { return true }
        if encounter.templateId.lowercased().contains(needle) { return true }
        if encounter.state.word.lowercased().contains(needle) { return true }
        if let note = encounter.note,
           note.sections.contains(where: { $0.body.lowercased().contains(needle) }) {
            return true
        }
        if let transcript = encounter.transcript,
           transcript.segments.contains(where: { $0.text.lowercased().contains(needle) }) {
            return true
        }
        return false
    }

    /// Built once. This used to be constructed per date group, on every
    /// sidebar render, and the sidebar re-renders on every keystroke in its
    /// search field.
    private static let thisYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let otherYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    static func dayLabel(_ day: Date, today: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = calendar.isDate(day, equalTo: today, toGranularity: .year)
            ? thisYear
            : otherYear
        return formatter.string(from: day)
    }
}

// MARK: - Learned vocabulary

/// The rewriting half of the learned vocabulary, with the file left behind.
enum LearnedTermRewriting {
    /// Case-insensitive, every occurrence, one pass.
    ///
    /// This used to search the text as it was being rewritten, which meant a
    /// replacement containing its own search term matched itself: a rule of
    /// `cetir` → `cetirizine` produced `cetirizineizineizine…` until a
    /// twenty-iteration cap stopped it. The cap hid the bug rather than fixing
    /// it. Scanning the original and appending to an output that is never
    /// searched removes the class of failure entirely — a unit test found this
    /// on the first run.
    ///
    /// Longest term first, so the more specific rule wins when two could match
    /// at the same position, and the result does not depend on dictionary
    /// ordering.
    static func rewrite(_ text: String, using terms: [String: String]) -> (String, Int) {
        guard !terms.isEmpty else { return (text, 0) }
        let ordered = terms
            .filter { !$0.key.isEmpty }
            .sorted { $0.key.count > $1.key.count }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        var hits = 0

        while index < text.endIndex {
            var matched = false
            for (heard, replacement) in ordered {
                guard let range = text.range(
                    of: heard,
                    options: .caseInsensitive,
                    range: index..<text.endIndex
                ), range.lowerBound == index else { continue }
                result += replacement
                hits += 1
                index = range.upperBound
                matched = true
                break
            }
            if !matched {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return (result, hits)
    }

    /// Apply to a transcript, and drop name checks the vocabulary has already
    /// resolved — asking about a term the practice has settled is noise.
    static func apply(
        to transcript: Transcript,
        using terms: [String: String]
    ) -> (Transcript, Int) {
        guard !terms.isEmpty else { return (transcript, 0) }
        var transcript = transcript
        var applied = 0
        for index in transcript.segments.indices {
            let (text, hits) = rewrite(transcript.segments[index].text, using: terms)
            if hits > 0 {
                transcript.segments[index].text = text
                applied += hits
            }
        }
        if applied > 0 {
            transcript.nameChecks = transcript.nameChecks?.filter { check in
                terms[check.heard.lowercased()] == nil
            }
        }
        return (transcript, applied)
    }
}
