//
// CaptureVault.swift
//
// Where a failed capture waits for its retry.
//
// The plan's rule: a transcription failure must not be a lost session. Before
// this file, `stopAndDraft`'s error path deleted the recording — the one
// thing the clinician cannot re-live — and told them to record again. For a
// consultation that is not a recovery path, it is a loss.
//
// The vault is the smallest honest answer:
//
// * **Sealed.** Every file it keeps — the audio, the recognised words and the
//   metadata — is AES-GCM sealed with a key from the Keychain, created for this
//   purpose and never written next to the files. Sealing only the audio left
//   the transcript text, which is the more sensitive artifact, in plaintext.
// * **Local only.** Files live in the app's sandboxed Application Support,
//   next to the encrypted store. Nothing reads them but this process; there
//   is no upload path and the network-surface guard keeps it that way.
// * **Time-limited.** Twenty-four hours, then gone on the next launch. A
//   recovery is a second chance, not an archive; the plan's §4-B set the
//   pilot policy and this implements exactly that.
// * **Fail closed.** A vault file that will not open (wrong key, truncated
//   write, disk corruption) is reported and deleted, never shown as
//   plaintext and never silently ignored. Orphaned files — a crash between
//   the audio and the metadata write, or a deleted metadata file — are swept
//   on the same pass, so nothing sits outside the retention rule.
//

import CryptoKit
import Foundation

struct CaptureVault {
    /// The pilot retention policy, from the improvement plan §4-B.
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    enum VaultError: LocalizedError {
        case sealed
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .sealed: "A saved recording could not be opened on this Mac."
            case .unreadable(let detail): "A saved recording could not be read: \(detail)"
            }
        }
    }

    let directory: URL
    private let key: SymmetricKey

    /// The designated initialiser, exposed for tests: a vault pointed at any
    /// directory with any key. Production goes through `open()`.
    init(directory: URL, key: SymmetricKey) {
        self.directory = directory
        self.key = key
    }

    // MARK: - Files

    private func audioURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).audio")
    }

    private func metaURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func segmentsURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).segments")
    }

    private func sealedWrite(_ data: Data, to url: URL) throws {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw VaultError.sealed
        }
        try combined.write(to: url, options: .atomic)
    }

    private func openSealed(_ url: URL) throws -> Data {
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    // MARK: - Seal and open

    /// A capture failed after the microphone stopped. Seal what exists: the
    /// audio always, the segments when recognition got that far.
    ///
    /// Atomic writes throughout — a crash mid-save must leave the previous
    /// state, not a truncated ciphertext nobody can open. A save that fails
    /// partway removes what it wrote, so it cannot leave a half-recovery that
    /// the list will never show.
    func seal(
        id: String,
        audio: URL,
        capture: RecoverableCapture,
        segments: [RecognisedSegment]?
    ) throws {
        do {
            let audioData = try Data(contentsOf: audio)
            try sealedWrite(audioData, to: audioURL(id))
            if let segments {
                let payload = try encode(CapturedSegments(
                    capture: capture,
                    segments: segments
                ))
                try sealedWrite(payload, to: segmentsURL(id))
            }
            let meta = try encode(capture)
            try sealedWrite(meta, to: metaURL(id))
        } catch {
            // Never leave the audio of a failed seal behind. It is the one file
            // that makes the failure expensive, and the caller can still tell
            // the clinician it could not be saved.
            destroy(id: id)
            throw error
        }
    }

    /// Re-open the audio for a retry. A file that will not open fails closed:
    /// the retry is refused with an honest error, not a half-decrypted guess.
    func unsealAudio(id: String) throws -> Data {
        try openSealed(audioURL(id))
    }

    /// The words already recognised for a `.recognised` retry.
    func openSegments(id: String) throws -> (capture: RecoverableCapture, segments: [RecognisedSegment]) {
        let data = try openSealed(segmentsURL(id))
        let payload = try decode(CapturedSegments.self, from: data)
        return (payload.capture, payload.segments)
    }

    func capture(id: String) -> RecoverableCapture? {
        guard let data = try? openSealed(metaURL(id)) else { return nil }
        return try? decode(RecoverableCapture.self, from: data)
    }

    /// Every recovery the vault can still prove it holds.
    ///
    /// A metadata file that will not open is destroyed rather than hidden: the
    /// audio and words it belonged to are unrecoverable, and leaving them on
    /// disk would keep clinical material past the policy for a record nobody
    /// can retry. A crash between the audio and metadata writes leaves the same
    /// kind of orphan; `sweepOrphans()` removes those.
    func list() -> [RecoverableCapture] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        var captures: [RecoverableCapture] = []
        for url in urls where url.pathExtension == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            if let capture = capture(id: id) {
                captures.append(capture)
            } else {
                NSLog("Klinote: a saved capture could not be opened and was removed")
                destroy(id: id)
            }
        }
        return captures.sorted { $0.startedAt > $1.startedAt }
    }

    /// The retry succeeded (or the clinician chose to let it go). Everything
    /// the recovery kept is removed — audio, segments, metadata. Returns false
    /// when a file could not be removed, so the caller can say so rather than
    /// claim a deletion that did not happen.
    @discardableResult
    func destroy(id: String) -> Bool {
        var removed = true
        for url in [audioURL(id), metaURL(id), segmentsURL(id)] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                removed = false
                NSLog("Klinote: could not remove a saved capture file: %@", error.localizedDescription)
            }
        }
        return removed
    }

    /// Remove files with no readable metadata, so a crash between writes or a
    /// corrupted metadata file cannot leave clinical material on disk forever.
    @discardableResult
    func sweepOrphans() -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let metadataIDs = Set(
            urls
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
        var orphanIDs = Set<String>()
        for url in urls where ["audio", "segments"].contains(url.pathExtension) {
            let id = url.deletingPathExtension().lastPathComponent
            if !metadataIDs.contains(id) {
                orphanIDs.insert(id)
            }
        }
        var removed = 0
        for id in orphanIDs where destroy(id: id) {
            removed += 1
        }
        return removed
    }

    /// The twenty-four hour rule. A recovery past its expiry is a second
    /// chance nobody came for; it is destroyed, and the count is returned so
    /// the shell can say so once instead of leaving silent deletions. Orphans
    /// are swept on the same pass and reported in the same count.
    @discardableResult
    func enforceRetention(now: Date = Date()) -> Int {
        var expired = sweepOrphans()
        for capture in list()
        where now.timeIntervalSince(capture.startedAt) > Self.retentionInterval {
            if destroy(id: capture.id) { expired += 1 }
        }
        return expired
    }

    /// Milliseconds of speech the recogniser confirmed, for a `.recognised`
    /// retry that wants to say how much survived.
    func capturedMilliseconds(id: String) -> UInt64? {
        guard let (_, segments) = try? openSegments(id: id) else { return nil }
        return segments.map(\.endMs).max()
    }
}

/// One file's worth: the capture and the words recognition produced before
/// it failed. Sealed together so a mismatch is impossible.
private struct CapturedSegments: Codable {
    let capture: RecoverableCapture
    let segments: [RecognisedSegment]
}
