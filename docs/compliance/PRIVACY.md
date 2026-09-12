# Privacy and data handling

**This document is an engineering statement of intent, not legal advice.** It
describes what the software does with data and what must be true before it is
used with real patients. Compliance with HIPAA, GDPR, the UK GDPR, the
Australian Privacy Act or any other regime is a separate assessment that has
**not** been performed.

## Data map

| Data | Where it lives | Notes |
|---|---|---|
| Audio | Never persisted by the engine | Buffered in memory for ASR, then dropped. The shell decides whether to retain a recording — v0 does not. |
| Transcript | SQLite (`transcripts.json`) in the local app database | Contains clinical content. |
| Note | SQLite (`notes.json`) in the local app database | Contains clinical content and template structure. |
| Encounter metadata | SQLite (`encounters`), including `patient_ref` | `patient_ref` is an opaque pseudonym. |
| Audit log | SQLite (`audit_log`), append-only | Actor, action, subject, timestamp. No clinical content. |
| Logs | Local stderr / shell logs | Must never contain clinical content or identifiers. |

Nothing on this list is transmitted anywhere. The Rust engine contains no
network code (enforced in CI). The **only** inbound network in the product is
the Swift shell's first-use download of the open-source whisper.cpp model
(`ggml-small.en-tdrz.bin`) from Hugging Face. Audio and notes never leave the
Mac.

## Identifiers

`Encounter::patient_ref` **must be an opaque pseudonym** — a random code minted
per encounter. It must never be:

- a name, initials, or any part of a name
- an MRN, NHS number, Medicare number, or insurance identifier
- a date of birth, or a date precise enough to identify
- an address, phone number, email or national ID

The mapping from pseudonym to patient lives **outside this system**, in the
clinic's own record system or an encrypted volume, and is never stored in this
repository or in the app database.

`clinician_ref` and `site_ref` are treated the same way: opaque codes.

## In place

| Property | How |
|---|---|
| **Encryption at rest** | SQLCipher. Key in the Keychain (`one.klinote.mac` / `sqlite-key`). Teaching-era plaintext files are renamed `*.unencrypted-bak` and a new ciphertext database is created. |
| **Retention policy** | Per practice: keep forever, or 3 / 12 / 36 months. Expired notes are purged at launch, and the setting says which. |
| **Real delete** | Hard `DELETE`, then `VACUUM`, so the freed pages are not left in the database file, plus an audit entry recording the count and the cutoff and never the content. The app tells the clinician "this is a real delete, not a flag", and a test reads the database file to check that the text is actually gone. |

## What is missing, and blocks real patient data

| Gap | Why it matters | Fix |
|---|---|---|
| **No access control beyond the key** | Any process running as the user can read the database once the Keychain has released the key. | Consider per-practice database files, and a review of the Keychain access policy. |
| **No export/portability story** | Clinicians have a right to their data. | Documented export format and a one-command backup. |
| **No BAA/DPA position** | Even though no data is processed by us, some practices require paperwork. | Written data-handling statement; counsel review before enterprise sales. |
| **Not sandboxed** | The app can read and write anything the user can. The sandbox is what would contain a memory-safety bug in the C++ that parses untrusted input — Whisper reading audio, llama.cpp reading a downloaded model — and hospital IT review asks about it. | Enable the sandbox and migrate the database, models and Keychain item into the container. Mandatory for the Mac App Store; optional for direct distribution, which is what 0.1.x is. Cheapest before there are installs to migrate. |
| **Not notarized** | A downloaded copy is refused by Gatekeeper until the clinician works around it. | Store notarization credentials and run `NOTARY_PROFILE=klinote scripts/release.sh`. See [`RELEASING.md`](../engineering/RELEASING.md). |

## Concierge-sprint rules

During validation (`docs/product/VALIDATION-PLAN.md`) we handle real
consultations, so:

1. Mint a fresh random `patient_ref` per encounter; keep the mapping in an
   encrypted volume outside this repo, and destroy it at the end of the pilot.
2. Store pilot databases outside the repository, in an encrypted volume.
3. Delete recordings and transcripts at the end of each encounter's review
   unless the clinician explicitly asks us to keep them.
4. Never paste clinical content, transcripts or notes into this repository, a
   chat tool, an issue tracker or an email thread longer than necessary to
   deliver the note.
5. Prefer transcripts over audio wherever the encounter permits it.

## Telemetry

None. No analytics, no crash reporting, no usage statistics, no "phone home on
first launch". The absence is a product feature and is enforced by
[ADR 0002](engineering/ADR/0002-local-only-privacy-posture.md).

## Incident response

If a device holding pilot data is lost or compromised:

1. Document what was on it, in what form, and whether it was encrypted.
2. Notify affected clinicians promptly and honestly.
3. Rotate any credentials that touched the device.
4. Record the incident and the fix in this document.

## Before any enterprise or practice-level sale

- [x] Encryption at rest implemented and verified.
- [x] Retention and deletion implemented. The *policy wording* for practices —
      what to choose and why — is still to write.
- [ ] Written data-handling statement reviewed by counsel.
- [ ] Security review of the app's entitlements, update mechanism and signing.
- [ ] A clear answer to "who can see the data?" — which must be "nobody but the
      clinician".
