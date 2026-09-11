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
import FoundationModels

enum NoteDrafter {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    static var unavailableReason: String? {
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
        return "On-device note drafting needs macOS 26 or later."
    }

    /// Returns a model-drafted note, or nil to keep the rule-based draft.
    static func draft(
        transcript: Transcript,
        template: TemplateSummary,
        encounterId: String
    ) async -> ClinicalNote? {
        if #available(macOS 26.0, *) {
            return await draftWithFoundationModels(
                transcript: transcript,
                template: template,
                encounterId: encounterId
            )
        }
        return nil
    }

    @available(macOS 26.0, *)
    private static func draftWithFoundationModels(
        transcript: Transcript,
        template: TemplateSummary,
        encounterId: String
    ) async -> ClinicalNote? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let utterances = numberedUtterances(from: transcript)
        guard !utterances.isEmpty else { return nil }

        let sectionList = template.sections.map { section in
            let flag = section.required ? "required" : "optional"
            return "- \(section.key) (\(flag)): \(section.title)"
        }.joined(separator: "\n")

        let transcriptBlock = utterances.map { item in
            "[\(item.index)] \(item.role): \(item.text)"
        }.joined(separator: "\n")

        // Phlox-style (MIT, bloodworks-io/phlox): small local models one-shot a whole
        // note poorly. Extract per template field as JSON, then a brevity pass.
        // Klinote's addition: every sentence cites transcript indices so the margin works.
        let extractInstructions = """
        You extract clinical documentation from a consultation transcript for a qualified clinician.
        Work only from the transcript. Do not invent findings, diagnoses, drugs, or plans.
        For each field, return only the most relevant points. Empty sentences if nothing belongs there.
        Each sentence must cite one or more utterance indices from the transcript.
        Prefer the patient's words for history and symptoms; the clinician's for examination, assessment and plan.
        Output JSON only.
        """

        let extractPrompt = """
        Extract relevant information for each field from the transcript.

        Template \(template.id) — \(template.name)
        Fields:
        \(sectionList)

        Transcript:
        \(transcriptBlock)

        Return ONLY JSON:
        {"sections":[{"key":"subjective","sentences":[{"text":"...","evidence":[1]}]}]}
        """

        let refineInstructions = """
        You are an editing assistant for a clinician's own records.
        1. Remove phrases like 'the doctor says' or 'the patient says'.
        2. Be brief. 'Patient feels tired' becomes 'Feels tired'. 'Follow-up appointment to review blood tests in 6 months' becomes 'Review in 6 months with bloods'.
        3. Use common medical abbreviations where they are unambiguous.
        4. Do not change which section a sentence belongs to.
        5. Do not add facts. Do not drop evidence indices.
        6. Keep the same JSON shape.
        """

        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                instructions: extractInstructions
            )
            let extracted = try await session.respond(to: extractPrompt)
            var draft = try parseDraft(from: extracted.content)

            let refineSession = LanguageModelSession(
                model: SystemLanguageModel(guardrails: .permissiveContentTransformations),
                instructions: refineInstructions
            )
            if let extractedJSON = try? jsonString(from: draft) {
                let refined = try await refineSession.respond(
                    to: "Edit this draft. Keep every evidence array unchanged.\n\(extractedJSON)"
                )
                if let polished = try? parseDraft(from: refined.content) {
                    draft = polished
                }
            }

            return assembleNote(
                draft: draft,
                transcript: transcript,
                utterances: utterances,
                template: template,
                encounterId: encounterId
            )
        } catch {
            NSLog("Klinote: on-device note draft failed: \(error.localizedDescription)")
            return nil
        }
    }

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

    private static func parseDraft(from raw: String) throws -> LLMDraft {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            json = String(trimmed[start...end])
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8) else {
            throw KlinoteCoreError.malformedResponse
        }
        return try JSONDecoder().decode(LLMDraft.self, from: data)
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

        let sections: [NoteSection] = template.sections.map { spec in
            let drafted = draft.sections.first { $0.key == spec.key }
            var sentences: [NoteSentence] = []
            for item in drafted?.sentences ?? [] {
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.split(separator: " ").count >= 2 else { continue }
                let evidence = item.evidence.compactMap { byIndex[$0]?.segmentID }
                guard !evidence.isEmpty else { continue }
                evidence.forEach { used.insert($0) }
                sentences.append(NoteSentence(text: text, evidence: evidence, ambiguous: evidence.count != 1))
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
