//
// NoteRouting.swift
//
// Where an extracted statement belongs in the note.
//
// This lives in Domain because it is pure logic over values — no model, no UI,
// no FFI — and because it decides clinical placement, which is not something to
// leave untested. It was previously tangled into `NoteDrafter`'s assembly pass,
// where the only way to check it was an end-to-end bench that needs Apple
// Intelligence and a language model to run. It was rewritten three times in one
// day in response to failures nobody could reproduce without a model.
//
// The behaviour it encodes, all of it learned the hard way (`NoteDrafter` has the
// accounts): a statement the model filed under the wrong field has no rival, so
// de-duplicating cannot fix it — it has to be able to *move*. Routing is by the
// field's own `cues`, the clinician-editable vocabulary the rule-based generator
// already routes on, so there is one definition of what a field is for.
//

import Foundation

enum NoteRouting {
    /// One statement the drafter produced, and the field the model chose.
    struct Claim: Equatable {
        /// Index into the template's sections.
        let modelChose: Int
        let text: String
    }

    /// How strongly a statement's words match a field's own vocabulary.
    ///
    /// Deliberately a plain substring count: `cues` are written by clinicians as
    /// words and short phrases ("safety net", "come back", "mg"), and matching
    /// them literally is what the rule-based generator already does.
    static func cueScore(_ text: String, cues: [String]) -> Int {
        let lowered = text.lowercased()
        return cues.reduce(into: 0) { total, cue in
            if !cue.isEmpty && lowered.contains(cue.lowercased()) {
                total += 1
            }
        }
    }

    /// Resolve every claim's destination.
    ///
    /// - Parameters:
    ///   - claims: statements in the order the drafter produced them.
    ///   - sectionCues: each template field's cues, in template order.
    ///   - margin: how much better another field must score before a statement
    ///     moves. At 1 a coin-flip routing decision would override the model;
    ///     the default of 2 exists so only a *clear* mismatch moves.
    /// - Returns: one entry per claim — the field index it belongs in, or `nil`
    ///   when the same words already won a place in a better-matched field.
    ///
    /// A claim whose text matches nothing anywhere keeps the model's choice: a
    /// routing decision made on no evidence is worse than the model's guess.
    static func resolve(
        claims: [Claim],
        sectionCues: [[String]],
        margin: Int = 2
    ) -> [Int?] {
        guard !claims.isEmpty, !sectionCues.isEmpty else {
            return claims.map { _ in nil }
        }

        // 1. Where each claim belongs.
        var destination: [Int] = claims.map { claim in
            let scores = scores(for: claim, sectionCues: sectionCues)

            // A model index outside the template is not a destination.
            guard claim.modelChose >= 0, claim.modelChose < scores.count else {
                return scores.indices.max(by: { scores[$0] < scores[$1] }) ?? 0
            }
            guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else {
                return claim.modelChose
            }
            return scores[best] >= scores[claim.modelChose] + margin ? best : claim.modelChose
        }

        // 2. One statement, one field. Where the same words were offered more
        //    than once, the better-matched field keeps them; ties go to the
        //    claim that came first, so the answer does not depend on the order
        //    the model happened to answer the fields in.
        var winner: [String: Int] = [:]
        for (index, claim) in claims.enumerated() {
            let fingerprint = fingerprint(of: claim.text)
            guard let incumbent = winner[fingerprint] else {
                winner[fingerprint] = index
                continue
            }
            let challenger = scores(for: claims[index], sectionCues: sectionCues)[destination[index]]
            let current = scores(for: claims[incumbent], sectionCues: sectionCues)[destination[incumbent]]
            if challenger > current {
                winner[fingerprint] = index
            }
        }

        let surviving = Set(winner.values)
        for index in claims.indices where !surviving.contains(index) {
            destination[index] = -1
        }
        return destination.map { $0 < 0 ? nil : $0 }
    }

    /// Same words, ignoring case and surrounding space.
    static func fingerprint(of text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scores(for claim: Claim, sectionCues: [[String]]) -> [Int] {
        sectionCues.map { cueScore(claim.text, cues: $0) }
    }
}
