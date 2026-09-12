//
// TaskBoard.swift
//
// What the consult asked for, as the shell shows it.
//
// One read fills `all`. Everything the interface asks for is derived from that
// in memory — the still-to-do list, and the tick beside each sentence — so a
// view body can ask about a sentence without reaching the store. Holding this
// as its own value keeps that invariant in one place instead of spread across
// a view model that also records audio.
//

import Foundation

struct TaskBoard {
    /// Every task, open or done, as of the last read.
    private(set) var all: [ConsultTask] = []
    /// Open tasks paired with their consult, for the still-to-do list.
    private(set) var openRows: [(task: ConsultTask, encounter: Encounter)] = []
    /// The selected consult's tasks, keyed by the sentence they came from.
    private(set) var index: [String: ConsultTask] = [:]

    var openCount: Int { openRows.count }

    /// Rebuild from one read. `selection` decides which consult's index is
    /// live.
    static func build(
        tasks: [ConsultTask],
        encounters: [Encounter],
        selection: String?
    ) -> TaskBoard {
        var board = TaskBoard()
        board.all = tasks
        board.openRows = TaskViews.openRows(tasks: tasks, encounters: encounters)
        board.index = TaskViews.index(tasks: tasks, encounterID: selection)
        return board
    }

    /// The tick for a sentence of the selected consult, or nil.
    ///
    /// Called from a view body once per sentence, so it is a dictionary
    /// lookup and cannot be anything else.
    func task(for sentence: String, in encounterID: String) -> ConsultTask? {
        index[sentence]
    }
}
