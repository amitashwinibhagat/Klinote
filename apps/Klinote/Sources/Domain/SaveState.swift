//
// SaveState.swift
//
// What the shell knows about whether a mutation reached the encrypted store,
// as values rather than as a silence that looks like success.
//
// Two rules this exists to enforce, both from the improvement plan:
//
// * A mutation that failed to persist must never present as saved. The screen
//   said "Saved" while the store said no — the exact failure the plan's
//   Phase 1 names first.
// * Review is a claim about one revision. `ClinicalNote.reviewState` is what
//   the store round-trips, so approval must move that field, not just the
//   shell's own encounter state — otherwise the approved note reloads as a
//   draft and the clinician's decision is quietly gone.
//

import Foundation

/// The persistence status of the latest mutation attempt on a session.
enum SaveOutcome: Equatable {
    /// Written and confirmed by the store.
    case saved
    /// The store refused; the in-memory copy is the only copy.
    case failed(String)
}

/// What a session's save status is, for the letterhead.
///
/// A derived view: the encounter's own save outcome, or the steady state.
enum SaveStatus: Equatable {
    case saved
    case unsaved(String)

    var word: String {
        switch self {
        case .saved: "Saved on this Mac"
        case .unsaved(let reason): "Not saved — \(reason)"
        }
    }

    var isUnsaved: Bool {
        if case .unsaved = self { return true }
        return false
    }
}

/// Decisions about review, as pure functions over values.
enum ReviewDecision {
    /// The review state a note carries after a **human** edits it.
    ///
    /// Always "edited":
    ///
    /// * from "draft" — a human moved the note out of Draft, which is exactly
    ///   what the engine's contract allows only a person to do;
    /// * from "approved" — what was approved is not what is on screen now, so
    ///   that revision's approval is spent. "edited" keeps the fact that a
    ///   human has been here without claiming the new text was signed off;
    /// * from "edited" — unchanged.
    ///
    /// The machine never calls this: a machine path has its own function
    /// below, and the two must never be confused.
    static func stateAfterHumanEdit(current: String) -> String {
        "edited"
    }

    /// The review state a note carries after the **machine** writes it again —
    /// a Quire redraft, a voice swap, any path that replaces the prose without
    /// a person in the loop.
    ///
    /// Always "draft": this revision is one no human has seen. Letting a
    /// redraft inherit "edited" or "approved" would put a review claim on
    /// text nobody reviewed — the same lie as approving silently, pointed the
    /// other way.
    static func stateAfterMachineRedraft() -> String {
        "draft"
    }

    /// The review state after an undo restores an earlier revision.
    ///
    /// Undo is a human action on content, but it is not the explicit review
    /// action. Restoring an approved revision must not put the `approved`
    /// claim back on screen — the plan says undo does not reapprove, and
    /// AGENTS reserves Approved for the File note action. The content is
    /// restored; the approval is not.
    static func stateAfterUndo(restored: String) -> String {
        restored == "approved" ? "edited" : restored
    }
}

/// A capture that outlived its own success: the recording is safe, the words
/// are not yet a note. Sealed encrypted by the vault, offered on the desk
/// with Retry or Discard.
///
/// Lives in Domain because it is a value the whole pipeline talks about —
/// the app model creates it, the vault seals it, the desk shows it — and
/// because the headless test bundle compiles this directory.
struct RecoverableCapture: Codable, Identifiable, Equatable {
    /// Stable identity: a retry files one encounter, never a duplicate.
    let id: String
    let patientRef: String
    let discipline: String
    let templateId: String
    let startedAt: Date
    let heldMs: UInt64
    /// Milliseconds of audio confirmed written before capture stopped, when
    /// known. The honest answer to "how much of the session do I have?".
    let capturedMs: UInt64?
    /// Which stage failed: the words were never recognised, or recognised
    /// but never drafted. A drafting retry must not re-run the microphone's
    /// work, and a recognition retry must not need the session again.
    let stage: Stage
    let failure: String

    enum Stage: String, Codable {
        /// Recognition never completed; the audio is the only source.
        case captured
        /// Segments are saved beside the audio; retry starts at drafting.
        case recognised
    }
}
