//
// diarize-bench.swift
//
// Headless harness for the turn-detection question: given a recording of a
// two-voice consultation, how often does the engine put the right speaker on a
// segment?
//
// It takes the same path the app takes — recognise with `SpeechAnalyzer`, hand
// the segments and the recording to the Rust engine over the C ABI — because the
// thing being measured is the whole chain, not a function in isolation.
//
// It prints one JSON object on stdout:
//
//   {"ok":true,
//    "speakers":[{"id":0,"role":"clinician"},…],
//    "segments":[{"start_ms":…,"end_ms":…,"text":"…","speaker":0,"role":"clinician"},…]}
//
// `scripts/diarize-bench.py` synthesises the audio, knows which voice spoke when,
// and does the scoring. Building this needs `libscribe_core_ffi.a`; the script
// builds it.
//
// Deliberately NOT in `apps/Klinote/Sources` — it defines `@main`, it is not part
// of the app, and the design-token and network-surface guards scan Sources.
//

import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8)
    else {
        log("could not encode output")
        exit(1)
    }
    print(text)
}

@main
struct DiarizeBench {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            log("usage: diarize-bench <recording.wav>")
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])

        log("recognising…")
        let recognised = try await Transcriber.transcribe(file: url, vocabulary: [])
        log("  \(recognised.count) segments")

        let request: [String: Any] = [
            "template_id": "soap",
            "patient_ref": "diarize-bench",
            "discipline": "general_practice",
            "language": "en",
            "engine": Transcriber.engineName,
            "audio_path": url.path,
            "segments": recognised.map { segment -> [String: Any] in
                [
                    "start_ms": segment.startMs,
                    "end_ms": segment.endMs,
                    "text": segment.text,
                    "confidence": segment.confidence ?? NSNull(),
                ]
            },
        ]
        let requestJSON = String(
            data: try JSONSerialization.data(withJSONObject: request),
            encoding: .utf8
        )!

        guard let raw = requestJSON.withCString({ scribe_note_from_segments($0) }) else {
            log("the engine returned nothing")
            exit(1)
        }
        defer { scribe_string_free(raw) }

        guard let payload = try JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8))
            as? [String: Any],
            payload["ok"] as? Bool == true
        else {
            log("engine error: \(String(cString: raw).prefix(300))")
            exit(1)
        }

        let transcript = payload["transcript"] as? [String: Any] ?? [:]
        let speakers = (transcript["speakers"] as? [[String: Any]]) ?? []
        let rawSegments = (transcript["segments"] as? [[String: Any]]) ?? []

        // speaker id → role, so each segment carries the role the engine chose.
        var roleForSpeaker: [Int: String] = [:]
        for speaker in speakers {
            if let id = speaker["id"] as? Int, let role = speaker["role"] as? String {
                roleForSpeaker[id] = role
            }
        }
        log("  \(speakers.count) speaker(s), \(rawSegments.count) transcript segments")

        let outSegments: [[String: Any]] = rawSegments.map { segment in
            let speaker = segment["speaker"] as? Int ?? -1
            return [
                "start_ms": segment["start_ms"] ?? 0,
                "end_ms": segment["end_ms"] ?? 0,
                "text": segment["text"] ?? "",
                "speaker": speaker,
                "role": roleForSpeaker[speaker] ?? "unknown",
            ]
        }

        emit([
            "ok": true,
            "engine": transcript["engine"] ?? "",
            "speakers": speakers,
            "segments": outSegments,
        ])
    }
}
