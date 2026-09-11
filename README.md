# Local Clinical Scribe

**Ambient clinical documentation that never leaves the Mac.**

Hold record during a consultation. Get a structured, template-matched note —
auditable back to every sentence that was said. No cloud, no account, no
per-token bill, and no data-processing agreement, because no audio or text ever
leaves the device.

> **Status: engine v0.** The Rust core is complete and tested end to end
> (audio → transcript → structured note, plus a human-transcript path). There is
> **no UI yet** — the Swift shell is the next milestone. See
> [`docs/product/VALIDATION-PLAN.md`](docs/product/VALIDATION-PLAN.md) for why
> that ordering is deliberate.

---

## Why this exists

Cloud scribes cost $300–1,000 per clinician per month and require a BAA or
data-processing agreement. For solo and small practices that is both too
expensive and, in many jurisdictions, a compliance burden they would rather not
carry. Until 2026 the local alternative was not good enough to be useful.

It is now. Two things changed:

- **Apple's platform** (macOS 26/27) ships on-device speech recognition and a
  free, natively multimodal foundation model as system APIs.
- **Open models** (Whisper/Parakeet-class ASR, 9–27B-class reasoning, speaker
  diarisation) now run at usable speed on Apple Silicon.

This project takes the position that the durable value is therefore **not the
model** — it is the workflow: the note template, the routing, the completeness
check, the audit trail, and the last mile into the clinician's record.

## Quickstart

```bash
# Everything runs locally; no model download is required for v0.
cargo test --workspace

# What templates exist?
cargo run -p scribe-cli -- templates

# Human transcript in, structured note out (the concierge workflow).
cargo run -p scribe-cli -- note --transcript fixtures/sample-transcript.txt

# Persist the encounter, transcript, note and an audit entry.
cargo run -p scribe-cli -- note \
  --transcript fixtures/sample-transcript.txt \
  --db ./scribe.db \
  --patient-ref demo-001

# Trace a note.
cargo run -p scribe-cli -- audit --db ./scribe.db --subject <note-id>
```

Transcript format is forgiving — role prefixes are optional, timestamps are
optional, and untagged lines continue the previous speaker:

```text
CLINICIAN: Good morning, what brings you in today?
PATIENT: I've had a sore throat for four days.
[00:42] CLINICIAN: Any fever?
wrapped continuation of the same speaker
```

## What works today

| Capability | State |
|---|---|
| Note templates (SOAP, physio, psychology, dental, veterinary) | ✅ compiled in, validated, editable TOML |
| Rule-based note generation with evidence links | ✅ deterministic, no model |
| Completeness check for required sections | ✅ surfaces missing sections |
| "Unfiled statements" — never silently drop transcript content | ✅ |
| Plain-text transcript parsing (roles, timestamps, wrapped lines) | ✅ |
| WAV ingest, mono downmix, resampling, energy VAD | ✅ |
| Speaker diarisation (two-speaker turn-taking) | ✅ heuristic, labelled as such |
| SQLite store + append-only audit trail | ✅ |
| C ABI for the Swift shell | ✅ JSON envelopes |
| Real ASR engine (Whisper / Parakeet / SpeechAnalyzer) | ⛔ next milestone |
| Model-backed note generation | ⛔ next milestone |
| Swift/SwiftUI app | ⛔ next milestone |
| Encryption at rest | ⛔ required before real patient data |

## Architecture at a glance

```
Rust core (this repo)                         Swift shell (next milestone)
┌──────────────────────────────────┐          ┌───────────────────────────────┐
│ scribe-audio   ingest · VAD      │          │ AVAudioEngine capture         │
│ scribe-asr     ASR trait + mock  │          │ SpeechAnalyzer (macOS 26+)    │
│ scribe-diarize speaker turns     │◀─ FFI ──▶│ Foundation Models / AFM 3     │
│ scribe-note    templates · notes │  JSON    │ AX insertion into the EHR     │
│ scribe-pipeline orchestration    │          │ Menu bar · Keychain · StoreKit│
│ scribe-store   SQLite + audit    │          └───────────────────────────────┘
└──────────────────────────────────┘
```

The Rust core owns everything hot, portable and testable. Swift owns everything
that is genuinely macOS: capture, permissions, insertion, notarisation.
Rationale and rejected alternatives: [`docs/engineering/ADR/0001`](docs/engineering/ADR/0001-rust-core-swift-shell.md).

## Repository layout

| Path | What |
|---|---|
| `crates/scribe-core/` | Domain model: encounters, transcripts, templates, notes. No I/O, no models. |
| `crates/scribe-audio/` | WAV ingest, downmix, resampling, energy VAD. |
| `crates/scribe-asr/` | `AsrEngine` trait + deterministic mock. |
| `crates/scribe-diarize/` | `Diarizer` trait + two-speaker turn-taking heuristic. |
| `crates/scribe-note/` | Template library + rule-based generator. |
| `crates/scribe-pipeline/` | The single orchestration entry point. |
| `crates/scribe-store/` | SQLite persistence + append-only audit log. |
| `crates/scribe-ffi/` | C ABI for Swift. |
| `crates/scribe-cli/` | `scribe` binary — pipeline runner and concierge tool. |
| `templates/` | Note templates as TOML. |
| `fixtures/` | Synthetic transcripts. **Never real patient data.** |
| `docs/` | Product, engineering, compliance. Start at `AGENTS.md`. |

## Privacy

The workspace contains **no networking code**. Audio, transcripts and notes
exist only on the machine. Transcripts are stored as opaque, pseudonymous
references — a `patient_ref` is never a name, an MRN or a date of birth.

Encryption at rest and retention/deletion are **not yet implemented** and must
be before any real patient data is processed. See
[`docs/compliance/PRIVACY.md`](docs/compliance/PRIVACY.md).

## Licence

Proprietary. See `LICENSE`.
