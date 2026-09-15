//
// NoteDrafter.swift
//
// Local language model → SOAP (or other template) draft.
//
// Uses Apple's on-device Foundation Models (AFM). Nothing leaves the Mac.
// Every sentence must cite transcript utterance indices; citations that
// don't match a real utterance are dropped and the source line is unfiled.
// If the model is unavailable, callers keep the rule-based draft.
//

import Foundation
// Foundation Models ships with the macOS 26 SDK, and this app deploys to
// macOS 15. The framework is already optional at run time — every use below is
// behind `#available(macOS 26.0, *)` and the caller falls back to the
// rule-based draft — so it has to be optional at build time too, or the source
// cannot be compiled by anything but the newest Xcode.
#if canImport(FoundationModels)
import FoundationModels
#endif

enum NoteDrafter {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to draft notes with the on-device model."
            case .unavailable(.modelNotReady):
                return "The on-device language model is still downloading."
            case .unavailable:
                return "The on-device language model is not available."
            }
        }
        #endif
        return "On-device note drafting needs macOS 26 or later."
    }

    /// Returns a model-drafted note, or nil to keep the rule-based draft.
    static func draft(
        transcript: Transcript,
        template: TemplateSummary,
        encounterId: String
    ) async -> ClinicalNote? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await draftWithFoundationModels(
                transcript: transcript,
                template: template,
                encounterId: encounterId
            )
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)

    // MARK: - What the model is allowed to produce

    /// Guided generation, not "please reply with JSON".
    ///
    /// The framework constrains decoding to these shapes, so a truncated, chatty
    /// or half-finished reply cannot arrive as a malformed draft that silently
    /// loses a section. That is the difference the note bench measures: the
    /// hand-rolled JSON version scored 3/4 required sections with the
    /// examination findings filed under Assessment, because nothing stopped the
    /// model deciding for itself what a field was for.
    @available(macOS 26.0, *)
    @Generable
    struct GeneratedSentence {
        @Guide(description: "One clinical statement, in the way a clinician would write it.")
        var text: String

        @Guide(description: "The transcript utterance indices this statement came from, for example [3, 4].")
        var evidence: [Int]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedSection {
        @Guide(description: "Every statement in the transcript that belongs in this field.")
        var sentences: [GeneratedSentence]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedEntry {
        @Guide(description: "The field key, exactly as it was given.")
        var key: String

        @Guide(description: "The statements for this field.")
        var sentences: [GeneratedSentence]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedDraft {
        @Guide(description: "One entry per field, in the order the fields were given.")
        var sections: [GeneratedEntry]
    }

    // MARK: - The draft

    /// Reproducible, and not degenerate.
    ///
    /// **A clinical note that changes between runs is not a record.** Measured:
    /// two runs over the same fixture produced two different notes — one with
    /// the examination repeated in both Objective and Assessment, the other with
    /// the whole consultation dumped into Subjective and the unclinical closing
    /// line leaking into it. The default sampling promises nothing here.
    ///
    /// `greedy` is the obvious fix and it is *worse*: taking the single most
    /// likely continuation every time made the model answer "no statements" for
    /// Assessment, dropping the impression into `unassigned` on every run —
    /// reproducibly wrong. A **fixed seed** is deterministic across runs without
    /// forcing the model down its likeliest, laziest path. Same input, same
    /// note; no coin flip.
    ///
    /// Capped so a runaway reply cannot eat the context window.
    @available(macOS 26.0, *)
    private static var extractionOptions: GenerationOptions {
        GenerationOptions(
            sampling: .random(top: 50, seed: 20260915),
            maximumResponseTokens: 700
        )
    }

    @available(macOS 26.0, *)
    private static var refinementOptions: GenerationOptions {
        GenerationOptions(
            sampling: .random(top: 50, seed: 20260915),
            maximumResponseTokens: 1200
        )
    }

    @available(macOS 26.0, *)
    private static func draftWithFoundationModels(
        transcript: Transcript,
        template: TemplateSummary,
        encounterId: String
    ) async -> ClinicalNote? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        let utterances = numberedUtterances(from: transcript)
        guard !utterances.isEmpty else { return nil }

        // One field per request, again because it is measured: asking this model
        // for all four SOAP fields in one go returned a good *subjective* line
        // and stopped, leaving objective, assessment and plan empty on a
        // transcript that contained an examination, an impression and a plan. A
        // 3B model satisfies the first instruction and stops.
        //
        // The transcript is split into as many requests as it takes to fit the
        // context window, so the same code serves a two-minute consult and a
        // fifty-minute one. See `transcriptChunks`.
        let chunks = await transcriptChunks(of: utterances, model: model)

        var draft = LLMDraft(sections: [])
        var extractedAnything = false

        for spec in template.sections {
            var sentences: [LLMDraft.Sentence] = []
            var seen = Set<String>()
            var queue = chunks

            while let chunk = queue.popLast() {
                let found = await extractSection(
                    spec: spec,
                    transcriptBlock: render(chunk),
                    model: model
                )

                // Nothing came back, and there was more than one utterance to
                // blame. That is what an over-long request looks like from out
                // here — `Exceeded model context window size`, caught inside
                // `extractSection` and reported as an empty field. The budget is
                // an estimate of the per-request overhead, and an estimate that
                // is wrong must not silently empty a field: halve the request and
                // try again rather than accept the loss.
                if found.isEmpty && chunk.count > 1 {
                    let middle = chunk.count / 2
                    queue.append(Array(chunk[middle...]))
                    queue.append(Array(chunk[..<middle]))
                    continue
                }

                for sentence in found {
                    // Chunk boundaries can surface the same statement twice.
                    let key = sentence.text.lowercased()
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    sentences.append(sentence)
                }
            }

            if !sentences.isEmpty { extractedAnything = true }
            draft.sections.append(LLMDraft.Section(key: spec.key, sentences: sentences))
        }

        // A model that produced nothing at all has failed, and the caller should
        // keep the rule-based draft rather than an empty note.
        guard extractedAnything else { return nil }

        draft = await refine(draft, model: model)

        return assembleNote(
            draft: draft,
            transcript: transcript,
            utterances: utterances,
            template: template,
            encounterId: encounterId
        )
    }

    /// How many tokens of transcript one request may carry.
    ///
    /// `contextSize` and `tokenCount` are **macOS 26.4** APIs — the newer
    /// on-device model's context reporting, added between the 26.0 framework and
    /// this SDK. On 26.0–26.3 there is no way to ask, so this falls back to a
    /// deliberately small constant: too many requests is a slower note, too few
    /// is a truncated one.
    @available(macOS 26.0, *)
    private static func tokenBudget(model: SystemLanguageModel) -> Int {
        if #available(macOS 26.4, *) {
            // Instructions, the generated-content schema, and room for a reply.
            return max(512, model.contextSize - 1400)
        }
        return 1500
    }

    /// The real count where the OS can give it, an estimate where it cannot.
    @available(macOS 26.0, *)
    private static func tokenCount(of text: String, model: SystemLanguageModel) async -> Int {
        if #available(macOS 26.4, *) {
            return (try? await model.tokenCount(for: text)) ?? estimateTokens(of: text)
        }
        return estimateTokens(of: text)
    }

    /// Rough English estimate: about four characters to a token. Used only to
    /// decide where to cut, and only where the real count is unavailable.
    private static func estimateTokens(of text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Split the transcript so no single request can overflow the context window.
    ///
    /// `contextSize` is 4096 tokens on macOS 26, not the 8192 of the newer model,
    /// and this bench's own fixture runs to roughly a thousand. A fifty-minute
    /// consultation is many times that, and the previous code sent the whole
    /// thing in one prompt and let it truncate. Read the size at runtime rather
    /// than trusting either number.
    @available(macOS 26.0, *)
    private static func transcriptChunks(
        of utterances: [Utterance],
        model: SystemLanguageModel
    ) async -> [[Utterance]] {
        let budget = tokenBudget(model: model)

        var chunks: [[Utterance]] = []
        var current: [Utterance] = []

        for utterance in utterances {
            let candidate = current + [utterance]
            let tokens = await tokenCount(of: render(candidate), model: model)
            // A single utterance larger than the budget is still sent, on its
            // own: dropping it would lose what was said, which is the one thing
            // this product must never do.
            if tokens > budget && !current.isEmpty {
                chunks.append(current)
                current = [utterance]
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { chunks.append(current) }

        let resolved = chunks.isEmpty ? [utterances] : chunks
        // Counts only — no transcript text, no patient data. Worth having in a
        // local log: it is the difference between a note that fitted and one
        // that was quietly cut into pieces.
        NSLog(
            "Klinote: on-device draft used %d transcript chunk(s) for %d utterances (budget %d tokens)",
            resolved.count,
            utterances.count,
            budget
        )
        return resolved
    }

    private static func render(_ utterances: [Utterance]) -> String {
        utterances.map { "[\($0.index)] \($0.role): \($0.text)" }.joined(separator: "\n")
    }

    /// One template field, one request.
    ///
    /// Returns an empty array when the field genuinely has nothing in it, and
    /// also when the model answers unusably — the caller cannot tell the
    /// difference, and for one field the honest outcome is the same: the section
    /// is empty, and `RuleBasedGenerator` is still there to fill it.
    @available(macOS 26.0, *)
    private static func extractSection(
        spec: TemplateSectionSummary,
        transcriptBlock: String,
        model: SystemLanguageModel
    ) async -> [LLMDraft.Sentence] {
        let instructions = """
        You extract exactly one field of a clinical note from a consultation transcript for a qualified clinician.
        Work only from the transcript. Never invent findings, diagnoses, drugs or plans that are not in it.
        Extract EVERY statement in the transcript that belongs in this one field — a consultation usually yields several.
        Do not stop after the first one.
        A statement belongs in exactly one field. Never return a statement whose real place is another field, and never return the same statement twice.
        If the field genuinely has nothing in the transcript, return no statements.
        Prefer the patient's own words for history and symptoms; the clinician's for examination, assessment and plan.
        """

        // The template already says what each field means and which words signal
        // it — `guidance` and `cues` are the clinician-editable surface the
        // rule-based engine routes on. Withholding them and giving the model only
        // the field's title made it guess: it filed the examination findings under
        // Assessment and repeated the Subjective line under Objective.
        let prompt = """
        Field: \(spec.key) — \(spec.title)
        What belongs in this field: \(spec.guidance)
        Words that usually signal this field: \(spec.cues.joined(separator: ", "))

        Transcript:
        \(transcriptBlock)
        """

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedSection.self,
                options: extractionOptions
            )
            return response.content.sentences.map {
                LLMDraft.Sentence(text: $0.text, evidence: $0.evidence)
            }
        } catch {
            NSLog(
                "Klinote: on-device extraction failed for %@: %@",
                spec.key,
                error.localizedDescription
            )
            return []
        }
    }

    /// A brevity pass over the assembled draft.
    ///
    /// A polish that fails, garbles, or drops a field must not cost the clinician
    /// the extraction underneath it, so the result is discarded unless every
    /// field came back.
    @available(macOS 26.0, *)
    private static func refine(
        _ draft: LLMDraft,
        model: SystemLanguageModel
    ) async -> LLMDraft {
        guard let draftJSON = try? jsonString(from: draft) else { return draft }

        let instructions = """
        You are an editing assistant for a clinician's own records.
        1. Remove phrases like 'the doctor says' or 'the patient says'.
        2. Be brief. 'Patient feels tired' becomes 'Feels tired'. 'Follow-up appointment to review blood tests in 6 months' becomes 'Review in 6 months with bloods'.
        3. Use common medical abbreviations where they are unambiguous.
        4. Do not change which field a statement belongs to, and do not merge statements.
        5. Do not add facts. Do not drop, reorder or alter evidence indices.
        6. Keep every field, including the empty ones.
        """

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(
                to: "Edit this draft. Keep every evidence array unchanged.\n\(draftJSON)",
                generating: GeneratedDraft.self,
                options: refinementOptions
            )
            let polished = LLMDraft(
                sections: response.content.sections.map { entry in
                    LLMDraft.Section(
                        key: entry.key,
                        sentences: entry.sentences.map {
                            LLMDraft.Sentence(text: $0.text, evidence: $0.evidence)
                        }
                    )
                }
            )
            guard Set(polished.sections.map(\.key)) == Set(draft.sections.map(\.key)) else {
                return draft
            }

            // It must not lose a *statement*, and it must not gain one either.
            //
            // Losing was the first guard, added after a long consultation came
            // back with all four fields and fewer statements inside them. Gaining
            // is the second, added on macOS 27 after the brevity pass produced
            // "Plan to review in follow-up." — a sentence that is in no part of
            // the transcript. A brevity pass rewrites statements; it does not add
            // them, and it does not remove them. So the count must come back
            // exactly as it went in, and anything else means keep the draft.
            //
            // This is the last line of defence, not the grounding check — see the
            // note on `support` in `assembleNote`.
            let before = draft.sections.reduce(0) { $0 + $1.sentences.count }
            let after = polished.sections.reduce(0) { $0 + $1.sentences.count }
            guard after == before else {
                NSLog(
                    "Klinote: brevity pass changed the statement count (%d → %d); keeping the draft",
                    before,
                    after
                )
                return draft
            }
            return polished
        } catch {
            NSLog("Klinote: on-device brevity pass failed: \(error.localizedDescription)")
            return draft
        }
    }
    #endif

    private struct Utterance {
        let index: Int
        let segmentID: String
        let role: String
        let text: String
    }

    private struct LLMDraft: Codable {
        struct Section: Codable {
            var key: String
            var sentences: [Sentence]
        }
        struct Sentence: Codable {
            var text: String
            var evidence: [Int]
        }
        var sections: [Section]
    }

    private static func numberedUtterances(from transcript: Transcript) -> [Utterance] {
        transcript.segments.enumerated().compactMap { offset, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let role = transcript.speakers.first { $0.id == segment.speaker }?.role ?? "other"
            return Utterance(index: offset, segmentID: segment.id, role: role, text: text)
        }
    }

    private static func jsonString(from draft: LLMDraft) throws -> String {
        let data = try JSONEncoder().encode(draft)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        return string
    }

    private static func assembleNote(
        draft: LLMDraft,
        transcript: Transcript,
        utterances: [Utterance],
        template: TemplateSummary,
        encounterId: String
    ) -> ClinicalNote {
        let byIndex = Dictionary(uniqueKeysWithValues: utterances.map { ($0.index, $0) })
        var used = Set<String>()
        var missingRequired: [String] = []

        // One statement, one field — and the field's own cues decide which.
        //
        // The prompt says a statement belongs in exactly one field and the model
        // does not obey it. Asked for each field separately it has done all of
        // these, on the same fixture, across runs:
        //
        //   · put the examination in Objective *and* repeated it in Assessment;
        //   · put the impression and all four plan statements in Assessment, and
        //     offered Plan nothing at all, so the note was signed with no plan.
        //
        // The second is why de-duplicating is not enough: a statement offered
        // under a single wrong field has no rival, so first-come-first-served
        // keeps the mistake. It has to be able to *move*.
        //
        // The rules live in `NoteRouting`, in Domain, with unit tests: they were
        // rewritten three times in a day here, and nothing could check them
        // without a language model and four minutes of synthesis.
        struct Claim {
            let sectionIndex: Int
            let sentence: LLMDraft.Sentence
        }

        var claims: [Claim] = []
        for (sectionIndex, spec) in template.sections.enumerated() {
            let drafted = draft.sections.first { $0.key == spec.key }
            for sentence in drafted?.sentences ?? [] {
                claims.append(Claim(sectionIndex: sectionIndex, sentence: sentence))
            }
        }

        let destinations = NoteRouting.resolve(
            claims: claims.map {
                NoteRouting.Claim(modelChose: $0.sectionIndex, text: $0.sentence.text)
            },
            sectionCues: template.sections.map(\.cues)
        )

        // Which claim landed where, for the assembly pass below.
        var placement: [Int: Int] = [:]
        for (index, destination) in destinations.enumerated() {
            if let destination { placement[index] = destination }
        }

        let sections: [NoteSection] = template.sections.enumerated().map { sectionIndex, spec in
            var sentences: [NoteSentence] = []
            for (index, claim) in claims.enumerated() where placement[index] == sectionIndex {
                let item = claim.sentence
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.split(separator: " ").count >= 2 else { continue }
                let evidence = item.evidence.compactMap { byIndex[$0]?.segmentID }
                guard !evidence.isEmpty else { continue }

                evidence.forEach { used.insert($0) }
                sentences.append(
                    NoteSentence(
                        text: text,
                        evidence: evidence,
                        ambiguous: evidence.count != 1,
                        // `support` is set to supported here and then *corrected*
                        // before anyone sees it: the draft goes back through the
                        // core's grounding check in `AppModel.preferLocalDraft`
                        // (`KlinoteCore.verify`), which is the same
                        // `verify_support` every Rust drafting path runs.
                        //
                        // This line is the default, not the verdict. Demonstrated
                        // on macOS 27: the extractor produced "Plan to review in
                        // follow-up.", a sentence in no utterance, citing one that
                        // does not contain it. Nothing in this file catches that —
                        // the brevity-pass count guard covers the *polish* step and
                        // the invention happened before it. What catches it is the
                        // check across the boundary, plus the evidence margin: a
                        // clinician clicking the sentence sees the words it claims
                        // and they do not match.
                        support: "supported",
                        wording: "plain"
                    )
                )
            }
            let body = sentences.map(\.text).joined(separator: " ")
            let complete = !body.isEmpty
            if spec.required && !complete {
                missingRequired.append(spec.key)
            }
            return NoteSection(
                key: spec.key,
                title: spec.title,
                body: body,
                evidence: Array(Set(sentences.flatMap(\.evidence))),
                sentences: sentences,
                complete: complete
            )
        }

        let unassigned: [UnassignedStatement] = utterances.compactMap { item in
            guard !used.contains(item.segmentID) else { return nil }
            guard item.text.split(separator: " ").count >= 2 else { return nil }
            return UnassignedStatement(
                text: item.text,
                speakerRole: item.role,
                evidence: [item.segmentID]
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return ClinicalNote(
            id: UUID().uuidString,
            encounterId: encounterId,
            templateId: template.id,
            sections: sections,
            unassigned: unassigned,
            generatedAt: formatter.string(from: Date()),
            engine: "apple-foundation-models-phlox",
            reviewState: "draft",
            missingRequired: missingRequired,
            machineGenerated: true
        )
    }
}
