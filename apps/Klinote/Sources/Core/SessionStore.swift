//
// SessionStore.swift
//
// Every read and write of the encrypted store, in one place.
//
// The store is not free. Each call is a Keychain lookup, an SQLCipher key
// derivation and an sqlite open, measured at ~48 ms. That cost is the reason
// this type exists rather than a scattering of calls: `load()` is the only way
// to read, and it returns everything the shell needs in one pass, so a view
// body has no shape available to it that reaches the database.
//
// AppModel holds one of these and no longer knows about paths, keys, JSON
// envelopes or the C ABI.
//

import Foundation

/// Everything the shell needs from one read: the consults, and the tasks.
struct StoredWorld {
    var sessions: [StoredSession] = []
    var tasks: [ConsultTask] = []
    var purgedNotes: Int = 0
}

struct SessionStore {
    /// One read for the whole picture.
    ///
    /// Retention runs first and in the same pass, because it is the same
    /// connection and the same key derivation — doing it separately would pay
    /// the open twice.
    func load(retentionMonths: Int, now: Date = Date()) throws -> StoredWorld {
        var world = StoredWorld()
        if retentionMonths > 0,
           let cutoff = Calendar.current.date(
               byAdding: .month,
               value: -retentionMonths,
               to: now
           )
        {
            world.purgedNotes = try KlinoteCore.purge(before: cutoff)
        }
        world.sessions = try KlinoteCore.loadSessions()
        // An empty encounter id means every task, open or done, so the shell
        // can rebuild the checklist and the ticks from this one result.
        world.tasks = try KlinoteCore.tasks(encounterId: "")
        return world
    }

    func save(_ encounter: Encounter, clinician: String?) throws {
        guard let note = encounter.note, let transcript = encounter.transcript else { return }
        try KlinoteCore.saveSession(
            patientRef: encounter.patientRef,
            discipline: encounter.discipline,
            templateId: encounter.templateId,
            startedAt: encounter.startedAt,
            note: note,
            transcript: transcript,
            clinician: clinician
        )
    }

    func purge(months: Int, now: Date = Date()) throws -> Int {
        guard months > 0,
              let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now)
        else { return 0 }
        return try KlinoteCore.purge(before: cutoff)
    }

    /// A hard delete on this Mac. The record system is untouched.
    ///
    /// A referral letter or a patient's copy has its own row — it was saved
    /// like any other note — so it is deleted here too. Skipping it would
    /// leave orphans behind for every derived document.
    func delete(encounterID: String) throws {
        try KlinoteCore.deleteSession(id: encounterID)
    }

    // MARK: - Tasks

    func addTask(encounterID: String, text: String, sourceKey: String?) throws {
        try KlinoteCore.addTask(encounterId: encounterID, text: text, sourceKey: sourceKey)
    }

    func setTaskDone(id: String, done: Bool) throws {
        try KlinoteCore.setTaskDone(id: id, done: done)
    }

    func deleteTask(id: String) throws {
        try KlinoteCore.deleteTask(id: id)
    }
}
