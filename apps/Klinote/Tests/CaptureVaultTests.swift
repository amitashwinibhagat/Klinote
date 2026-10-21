//
// CaptureVaultTests.swift
//
// The vault's promises, tested against a temp directory and a test key — no
// Keychain, no ModelDownloader, no microphone. What is *wired* is proven by
// the app: `CaptureVault.open()` is the only call AppModel makes.
//
// These tests encode the plan's §4-B pilot policy: sealed at rest, fail
// closed on corruption, twenty-four hours then gone.
//

import CryptoKit
import XCTest

final class CaptureVaultTests: XCTestCase {
    private var directory: URL!
    private var vault: CaptureVault!
    private var audio: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("klinote-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vault = CaptureVault(directory: directory, key: SymmetricKey(size: .bits256))
        audio = directory.appendingPathComponent("source.wav")
        try Data("fake wav bytes".utf8).write(to: audio)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func capture(
        id: String = "enc-test0001",
        startedAt: Date = Date(),
        stage: RecoverableCapture.Stage = .captured
    ) -> RecoverableCapture {
        RecoverableCapture(
            id: id,
            patientRef: id,
            discipline: "psychology",
            templateId: "psychology",
            startedAt: startedAt,
            heldMs: 0,
            capturedMs: 5_000,
            stage: stage,
            failure: "test failure"
        )
    }

    private func segments() -> [RecognisedSegment] {
        [RecognisedSegment(startMs: 0, endMs: 5_000, text: "hello there", confidence: 0.9)]
    }

    // MARK: - Sealed at rest

    /// The audio on disk must not be the audio that went in. A vault that
    /// stored plaintext would make "encrypted recovery" a claim with nothing
    /// behind it.
    func testSealedAudioIsNotPlaintextOnDisk() throws {
        try vault.seal(id: "enc-test0001", audio: audio, capture: capture(), segments: nil)
        let onDisk = try Data(contentsOf: directory.appendingPathComponent("enc-test0001.audio"))
        XCTAssertNotEqual(onDisk, Data("fake wav bytes".utf8))
        XCTAssertTrue(onDisk.count > 12, "AES-GCM combined is ciphertext plus nonce plus tag")
    }

    // MARK: - Round trip

    /// The transcript text is the most sensitive thing the vault holds. The
    /// first version sealed only the audio and left `.segments` and `.json` as
    /// plaintext, so "encrypted recovery" was not true of the words.
    func testEveryVaultFileIsSealed() throws {
        let saved = capture(id: "enc-all00001", stage: .recognised)
        try vault.seal(
            id: saved.id,
            audio: audio,
            capture: saved,
            segments: segments()
        )
        for suffix in ["audio", "segments", "json"] {
            let url = directory.appendingPathComponent("\(saved.id).\(suffix)")
            let data = try Data(contentsOf: url)
            XCTAssertFalse(
                String(data: data, encoding: .utf8)?.contains("hello there") == true,
                "\(suffix) contains the recognised words in plaintext"
            )
            XCTAssertFalse(
                String(data: data, encoding: .utf8)?.contains(saved.patientRef) == true,
                "\(suffix) contains the pseudonym in plaintext"
            )
        }
    }

    /// A crash between the audio and metadata write leaves a file with no
    /// recovery the shell can offer. Retention must remove it, not leave it on
    /// disk forever.
    func testOrphanedVaultFilesAreSwept() throws {
        let orphan = "enc-orphan001"
        try Data("sealed-looking bytes".utf8)
            .write(to: directory.appendingPathComponent("\(orphan).audio"))
        try Data("sealed-looking bytes".utf8)
            .write(to: directory.appendingPathComponent("\(orphan).segments"))

        let removed = vault.enforceRetention(now: Date())

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(orphan).audio").path
            )
        )
    }

    func testSealThenUnsealReturnsTheAudio() throws {
        try vault.seal(id: "enc-test0001", audio: audio, capture: capture(), segments: nil)
        let opened = try vault.unsealAudio(id: "enc-test0001")
        XCTAssertEqual(opened, Data("fake wav bytes".utf8))
    }

    /// A `.recognised` capture carries its words: the whole point of the
    /// stage is that a drafting retry never re-runs recognition.
    func testSegmentsRoundTrip() throws {
        try vault.seal(
            id: "enc-test0002",
            audio: audio,
            capture: capture(id: "enc-test0002", stage: .recognised),
            segments: segments()
        )
        let (_, opened) = try vault.openSegments(id: "enc-test0002")
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened[0].text, "hello there")
        XCTAssertEqual(opened[0].endMs, 5_000)
    }

    // MARK: - Fail closed

    /// A truncated or tampered ciphertext must refuse to open. Returning
    /// partial plaintext here would be the worst possible failure.
    func testCorruptAudioFailsClosed() throws {
        try vault.seal(id: "enc-test0003", audio: audio, capture: capture(id: "enc-test0003"), segments: nil)
        let file = directory.appendingPathComponent("enc-test0003.audio")
        let data = try Data(contentsOf: file)
        try data.prefix(max(0, data.count - 5)).write(to: file)
        XCTAssertThrowsError(try vault.unsealAudio(id: "enc-test0003"))
    }

    /// A vault opened with a different key must not decrypt — the failure
    /// mode of reusing the store key if the store is ever re-keyed.
    func testWrongKeyFailsClosed() throws {
        try vault.seal(id: "enc-test0004", audio: audio, capture: capture(id: "enc-test0004"), segments: nil)
        let other = CaptureVault(directory: directory, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.unsealAudio(id: "enc-test0004"))
    }

    // MARK: - Retention

    /// The twenty-four hour rule, enforced where the plan set it: expired
    /// captures are destroyed, and everything they kept goes with them.
    func testExpiredCapturesAreDestroyed() throws {
        let cutoff = Date().addingTimeInterval(-25 * 60 * 60)
        let old = capture(id: "enc-old0001", startedAt: cutoff)
        try vault.seal(id: old.id, audio: audio, capture: old, segments: segments())
        let fresh = capture(id: "enc-fresh001", startedAt: Date())
        try vault.seal(id: fresh.id, audio: audio, capture: fresh, segments: segments())

        let removed = vault.enforceRetention(now: Date())

        XCTAssertEqual(removed, 1)
        let remaining = vault.list()
        XCTAssertFalse(remaining.contains { $0.id == old.id })
        XCTAssertTrue(remaining.contains { $0.id == fresh.id })
        XCTAssertThrowsError(try vault.unsealAudio(id: old.id), "the sealed audio went with it")
    }

    // MARK: - Destroy

    func testDestroyRemovesEverythingTheVaultKept() throws {
        let saved = capture(id: "enc-gone0001", stage: .recognised)
        try vault.seal(id: saved.id, audio: audio, capture: saved, segments: segments())
        vault.destroy(id: saved.id)
        XCTAssertTrue(vault.list().isEmpty)
        XCTAssertThrowsError(try vault.unsealAudio(id: saved.id))
        XCTAssertThrowsError(try vault.openSegments(id: saved.id))
        XCTAssertNil(vault.capture(id: saved.id))
    }
}
