# Nota

**Clinical notes that never leave the room.**

Hold record during a consultation. Get a structured, template-matched note —
auditable back to every sentence that was said. No cloud, no account, no
per-token bill, and no data-processing agreement, because no audio or text ever
leaves the device.

> **Status: M1.** The Rust engine is complete and tested (41 tests). The macOS
> app builds, launches, and renders the full review surface. There is **no real
> speech-recognition engine yet** — the default is a mock, and the app labels
> its bundled sample as synthetic in the document itself.
> Encryption at rest is not built, so **real patient data must not be used**
> with this build. See [`docs/compliance/PRIVACY.md`](docs/compliance/PRIVACY.md).

**Design is documented and authoritative.** Read [`PRODUCT.md`](PRODUCT.md),
[`DESIGN.md`](DESIGN.md) and [`docs/design/UX-PLAN.md`](docs/design/UX-PLAN.md)
before changing anything visual.

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
# Engine — everything runs locally; no model download is required.
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

# The macOS app
cd apps/Nota && xcodegen generate
xcodebuild -project Nota.xcodeproj -scheme Nota -configuration Release \
  -derivedDataPath /tmp/nota-dd build CODE_SIGNING_ALLOWED=NO
open /tmp/nota-dd/Build/Products/Release/Nota.app
```

The app lives in the menu bar (⌥⌘R to record, ⌘⇧N to open). It ships a
synthetic consultation so you can see a real draft — with its evidence in the
margin — before recording anything.

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
| macOS app: menu bar, recording strip, review window, settings | ✅ builds and launches |
| Sentence-level evidence: select a sentence, see the words behind it | ✅ the signature interaction |
| Note templates (SOAP, physio, psychology, dental, veterinary) | ✅ compiled in, validated, editable TOML |
| Rule-based note generation with per-sentence evidence | ✅ deterministic, no model |
| Completeness check for required sections | ✅ surfaces missing sections |
| "Unfiled statements" — never silently drop transcript content | ✅ |
| Plain-text transcript parsing (roles, timestamps, wrapped lines) | ✅ |
| WAV ingest, mono downmix, resampling, energy VAD | ✅ engine only — not yet wired to the UI |
| Speaker diarisation (two-speaker turn-taking) | ✅ heuristic, labelled as such |
| SQLite store + append-only audit trail | ✅ engine only |
| C ABI, statically linked into the app bundle | ✅ self-contained 3 MB bundle |
| Real ASR engine (Whisper / Parakeet / SpeechAnalyzer) | ⛔ next milestone |
| Model-backed note generation | ⛔ next milestone |
| Encryption at rest | ⛔ blocks real patient data |

## Architecture at a glance

```
Rust core (crates/)                          Swift shell (apps/Nota/)
┌──────────────────────────────────┐          ┌───────────────────────────────┐
│ scribe-audio   ingest · VAD      │          │ Menu bar · global hotkeys     │
│ scribe-asr     ASR trait + mock  │          │ Recording strip (NSPanel)     │
│ scribe-diarize speaker turns     │◀─ FFI ──▶│ Review window + margin        │
│ scribe-note    templates · notes │  static  │ Settings                      │
│ scribe-pipeline orchestration    │   lib    │ Design tokens (DESIGN.md)     │
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
| `apps/Nota/` | Swift/SwiftUI shell. `project.yml` is the source of truth; the `.xcodeproj` is generated. |
| `templates/` | Note templates as TOML. |
| `fixtures/` | Synthetic transcripts. **Never real patient data.** |
| `docs/design/` | UX plan, direction contract, states, keyboard map. |
| `PRODUCT.md` · `DESIGN.md` | Product truth and the visual system. |
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
