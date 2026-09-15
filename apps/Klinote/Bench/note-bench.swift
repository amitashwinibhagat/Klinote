//
// note-bench.swift
//
// Headless scoring harness for the note-writing path.
//
// Reads the same request JSON the old GGUF bench used on stdin and writes
// `{"ok": true, "note": …}` on stdout, so `scripts/note-bench.py` can score it
// against `fixtures/note-bench/gold-facts.json` unchanged.
//
// It compiles `Sources/Domain` and `Sources/Core/NoteDrafter.swift` against the
// real engine — no app, no Keychain, no store — because the question it asks is
// "does the on-device model write an acceptable note", and that question should
// be answerable without launching a clinical application.
//
// **The template comes from the engine, not from the request.** An earlier
// version of this file built its own `TemplateSummary` from the request and left
// `guidance` and `cues` empty, so the drafter was being asked to route clinical
// statements into fields it had been told nothing about — and the bench was
// measuring a prompt the app never sends. The prompt's whole routing surface is
// those two fields. Fetching the template through the same FFI call the app uses
// is what makes the number mean something.
//
// Deliberately NOT in `apps/Klinote/Sources`: it defines `@main`, it is not part
// of the app, and the design-token and network-surface guards scan Sources.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The subset of the bench request this harness needs.
struct BenchRequest: Decodable {
    struct Template: Decodable {
        struct Section: Decodable {
            let key: String
            let title: String
            var required: Bool?
        }
        let id: String
        let name: String
        let sections: [Section]
    }

    let transcript: Transcript
    let template: Template
}

enum Bench {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        print(text)
    }

    static func fail(_ message: String) -> Never {
        emit(["ok": false, "error": message])
        exit(1)
    }

    /// The real template, with its real `guidance` and `cues`.
    ///
    /// Falls back to the request's own sections only if the engine cannot be
    /// asked — and says so on stderr, because a run with empty cues is not
    /// measuring the product.
    static func template(id: String, fallback: BenchRequest.Template) -> TemplateSummary {
        if let raw = scribe_list_templates() {
            defer { scribe_string_free(raw) }
            let json = String(cString: raw)
            struct Envelope: Decodable {
                let ok: Bool
                let templates: [TemplateSummary]?
            }
            if let data = json.data(using: .utf8),
               let envelope = try? decoder.decode(Envelope.self, from: data),
               let match = envelope.templates?.first(where: { $0.id == id }) {
                return match
            }
            FileHandle.standardError.write(
                Data("  warning: engine had no template '\(id)'; using the request's bare sections\n".utf8)
            )
        }

        return TemplateSummary(
            id: fallback.id,
            name: fallback.name,
            discipline: "bench",
            version: "bench",
            description: "",
            voice: nil,
            family: "note",
            render: "sections",
            audience: "clinical",
            sections: fallback.sections.map {
                TemplateSectionSummary(
                    key: $0.key,
                    title: $0.title,
                    guidance: "",
                    required: $0.required ?? false,
                    cues: [],
                    actions: false
                )
            }
        )
    }
}

@main
struct NoteBench {
    static func main() async {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty else {
            Bench.fail("no request on stdin")
        }

        let request: BenchRequest
        do {
            request = try Bench.decoder.decode(BenchRequest.self, from: input)
        } catch {
            Bench.fail("could not read the request: \(error.localizedDescription)")
        }

        guard NoteDrafter.isAvailable else {
            Bench.fail(NoteDrafter.unavailableReason ?? "the on-device model is not available")
        }

        let template = Bench.template(id: request.template.id, fallback: request.template)
        let cueCount = template.sections.reduce(0) { $0 + $1.cues.count }
        FileHandle.standardError.write(
            Data("  template '\(template.id)': \(template.sections.count) fields, \(cueCount) cues\n".utf8)
        )
        guard cueCount > 0 else {
            Bench.fail("template '\(template.id)' arrived with no cues — the run would not measure the product")
        }

        let note = await NoteDrafter.draft(
            transcript: request.transcript,
            template: template,
            encounterId: request.transcript.encounterId
        )

        guard let note else {
            Bench.fail("the model returned no note")
        }

        guard let data = try? Bench.encoder.encode(note),
              let object = try? JSONSerialization.jsonObject(with: data),
              let encoded = object as? [String: Any]
        else {
            Bench.fail("could not encode the note")
        }

        Bench.emit(["ok": true, "note": encoded])
    }
}
