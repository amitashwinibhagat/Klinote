//
// LocalLlm.swift
//
// Dedicated local instruct GGUF (llama.cpp) for SOAP drafts. Runs as a sibling
// process so ggml does not clash with Whisper.
// Phlox extract → refine, with evidence indices. Nothing leaves the Mac.
//

import Foundation

enum LocalLlm {
    static var binary: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "scribe-llm")
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/scribe-llm")
    }

    static var isReady: Bool {
        FileManager.default.fileExists(atPath: ModelDownloader.noteFile.path)
            && (binary.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false)
    }

    static func draft(
        transcript: Transcript,
        template: TemplateSummary
    ) throws -> ClinicalNote {
        guard let binary else {
            throw NotaCoreError.engine("The local note engine is missing from the app bundle.")
        }
        let model = ModelDownloader.noteFile
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw NotaCoreError.engine("The note model is not downloaded.")
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var transcript = transcript
        if transcript.createdAt == nil {
            transcript.createdAt = ISO8601DateFormatter().string(from: Date())
        }
        let transcriptObject = try JSONSerialization.jsonObject(with: encoder.encode(transcript))
        let sections: [[String: Any]] = template.sections.map {
            [
                "key": $0.key,
                "title": $0.title,
                "required": $0.required,
            ]
        }
        let payload: [String: Any] = [
            "transcript": transcriptObject,
            "template": [
                "id": template.id,
                "name": template.name,
                "sections": sections,
            ],
        ]
        let stdin = try JSONSerialization.data(withJSONObject: payload)

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--model", model.path]
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        inPipe.fileHandleForWriting.write(stdin)
        try inPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(180)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning {
            process.terminate()
            throw NotaCoreError.engine("The note engine took too long.")
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(NoteEnvelope.self, from: data)
        guard envelope.ok, let note = envelope.note else {
            throw NotaCoreError.engine(envelope.error ?? "The note engine returned nothing.")
        }
        return note
    }
}
