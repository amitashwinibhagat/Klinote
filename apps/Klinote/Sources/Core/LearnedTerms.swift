//
// LearnedTerms.swift
//
// Corrections the clinician has already made once. When they accept a drug-name
// suggestion, that becomes this practice's vocabulary: the same mishearing is
// fixed next time instead of being asked about again.
//
// Two rules keep this honest:
//   1. It only ever learns from an explicit human acceptance. Never inferred.
//   2. A learned fix is announced, not silent. "2 learned corrections applied."
//

import Foundation

enum LearnedTerms {
    private static var file: URL {
        ModelDownloader.supportDirectory.appendingPathComponent("learned-terms.json")
    }

    /// heard (lowercased) → the wording this clinician uses.
    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: file),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    static func learn(heard: String, replacement: String) {
        let key = heard.lowercased()
        guard !key.isEmpty, !replacement.isEmpty else { return }
        var map = load()
        map[key] = replacement
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: file, options: .atomic)
        }
    }

    static func forget(_ heard: String) {
        var map = load()
        map.removeValue(forKey: heard.lowercased())
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: file, options: .atomic)
        }
    }

    static var count: Int { load().count }

    /// Apply the learned vocabulary to a transcript. Returns the rewritten
    /// transcript and how many substitutions were made.
    static func apply(to transcript: Transcript) -> (Transcript, Int) {
        let map = load()
        guard !map.isEmpty else { return (transcript, 0) }
        var transcript = transcript
        var applied = 0
        for index in transcript.segments.indices {
            let (text, hits) = rewrite(transcript.segments[index].text, using: map)
            if hits > 0 {
                transcript.segments[index].text = text
                applied += hits
            }
        }
        if applied > 0 {
            // A name check for a term we have already resolved is stale.
            transcript.nameChecks = transcript.nameChecks?.filter { check in
                map[check.heard.lowercased()] == nil
            }
        }
        return (transcript, applied)
    }

    /// Apply the learned vocabulary to pasted text.
    static func apply(to text: String) -> (String, Int) {
        rewrite(text, using: load())
    }

    private static func rewrite(_ text: String, using map: [String: String]) -> (String, Int) {
        var result = text
        var hits = 0
        for (heard, replacement) in map {
            guard result.range(of: heard, options: .caseInsensitive) != nil else { continue }
            var current = result
            var count = 0
            while let range = current.range(of: heard, options: .caseInsensitive) {
                current.replaceSubrange(range, with: replacement)
                count += 1
                if count > 20 { break }
            }
            result = current
            hits += count
        }
        return (result, hits)
    }
}
