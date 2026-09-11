# Architecture

## The shape of the system

Two layers with a hard boundary, because the two concerns pull in opposite
directions:

- **Rust core** — everything hot, portable, deterministic and testable. Model
  orchestration, audio DSP, diarisation, template rendering, note assembly,
  storage, audit. No Apple frameworks, no UI, no network.
- **Swift shell** — everything that is genuinely macOS. Microphone capture,
  `SpeechAnalyzer`, Foundation Models, Accessibility insertion, menu bar,
  Keychain, notarisation, StoreKit.

The boundary is a C ABI carrying JSON (`crates/scribe-ffi`). Rationale and the
alternatives we rejected: [ADR 0001](ADR/0001-rust-core-swift-shell.md).

```
┌──────────────────────────── Rust core ────────────────────────────┐
│                                                                    │
│  scribe-core ── domain model (ids, encounter, transcript,          │
│                 template, note). No I/O. No models.                │
│      ▲                                                             │
│      │                                                             │
│  scribe-audio   WAV ingest · downmix · resample · energy VAD       │
│  scribe-asr     AsrEngine trait · MockAsrEngine                    │
│  scribe-diarize Diarizer trait · TurnTakingDiarizer                │
│  scribe-note    TemplateLibrary · RuleBasedGenerator               │
│      │                                                             │
│      ▼                                                             │
│  scribe-pipeline  ScribePipeline — the ONLY orchestration point    │
│      │                                                             │
│      ├──────────────► scribe-store   SQLite + append-only audit    │
│      │                                                             │
│      ▼                                                             │
│  scribe-ffi (C ABI, JSON)   scribe-cli (concierge tool)            │
└────────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
            Swift shell (next)     CI / batch / validation
```

## Data flow: audio path

```
WAV / live buffer
  → AudioBuffer (mono f32)
  → resample_to(16 kHz)                 scribe-audio
  → detect_speech() → Vec<SpeechSpan>   energy VAD, no model
  → AsrEngine::transcribe()             MockAsrEngine today; SpeechAnalyzer / Whisper later
  → Diarizer::diarize()                 TurnTakingDiarizer today
  → RoleMap: SpeakerId → SpeakerRole    {0: Clinician, 1: Patient}, shell-correctable
  → Transcript { speakers, segments }   scribe-core
  → NoteGenerator::generate()           RuleBasedGenerator today
  → ClinicalNote { sections, evidence, missing_required, unassigned }
```

## Data flow: text path

```
plain text ("CLINICIAN: ...", optional [mm:ss], wrapped lines allowed)
  → parse_transcript_text() → Transcript
  → NoteGenerator::generate() → ClinicalNote
```

The text path exists so the product can run with **no model and no audio** —
which is what makes the concierge validation sprint possible today, and what
keeps CI model-free.

## Crate responsibilities and rules

| Crate | Owns | Must not |
|---|---|---|
| `scribe-core` | The vocabulary. Serde-friendly so the FFI and store can use it directly. | Do I/O, depend on audio/ML crates, or hold identifiers. |
| `scribe-audio` | Ingest, resample, VAD. | Know about ASR, notes or diarisation. |
| `scribe-asr` | The `AsrEngine` trait and a deterministic mock. | Guess at speakers, or touch the filesystem. |
| `scribe-diarize` | The `Diarizer` trait and a labelled heuristic. | Assign roles — that is `RoleMap`'s job. |
| `scribe-note` | Template loading/validation and generation. | Throw away transcript content. |
| `scribe-pipeline` | Orchestration, `RoleMap`, defaults. | Contain product logic that belongs in a stage. |
| `scribe-store` | Persistence and the audit log. | Delete audit rows. |
| `scribe-ffi` | The C ABI and its JSON envelopes. | Panic across the boundary. |
| `scribe-cli` | Argument parsing and rendering. | Duplicate pipeline logic. |

## The FFI contract

- Every return is a heap `*mut c_char` the caller frees with
  `scribe_string_free`. Null-safe.
- Every payload function returns `{"ok": true, ...}` or
  `{"ok": false, "error": "..."}`. Errors never panic across the boundary; a
  null or non-UTF-8 input pointer is an error envelope, not undefined behaviour.
- Input pointers that are dereferenced make the function `unsafe extern "C"`.
- `scribe_schema_version()` lets Swift assert compatibility at launch.

**When to migrate to `uniffi`:** as soon as the boundary needs *state* — a
streaming session handle, progress callbacks, or a loaded model. The JSON
envelope is a deliberate v0 simplification, not a destination.

## Concurrency and threading

- The core is synchronous and single-threaded by default. Capture and UI live
  in the shell.
- Trait objects in `ScribePipeline` are `Send + Sync`, so the shell can move
  the pipeline to a background task and keep the main thread free.
- Long work (ASR on a 20-minute consult) must not block the shell's main actor.
  The shell is responsible for that; the core does not spawn threads.
- Generation must be cancellable from the UI. When a real model is wired in,
  cancellation should be a `NoteGenerator`/`AsrEngine` concern rather than a
  pipeline concern — keep the trait boundary clean.

## Error model

One error type, `scribe_core::ScribeError`, coarse by design:

- `TemplateNotFound` / `InvalidTemplate` — configuration problems, surfaced at
  startup.
- `Audio` / `Transcription` / `Diarisation` — stage failures.
- `NoteGeneration` — generator failures.
- `Storage` — persistence.
- `InvalidInput` — caller error.

**Error messages never contain patient data.** They carry file paths, template
ids and library messages only.

## Testing strategy

| Layer | Approach |
|---|---|
| `scribe-core` | Pure unit tests: parsing, validation, markdown, completeness. |
| `scribe-audio` | Synthesised tones and silence — no fixtures on disk, no audio device. |
| `scribe-note` | The generated-note tests double as the routing specification. `never_drops_transcript_content` guards the contract. |
| `scribe-pipeline` | End-to-end audio and text runs with the mock engine. |
| `scribe-store` | In-memory SQLite round-trips, including audit ordering. |
| `scribe-ffi` | Envelope tests including malformed input and null-free. |

**Hard rule:** `cargo test --workspace` must pass with no model, no network and
no audio hardware. A test that needs a model is feature-gated and off by default.

## Privacy by construction

There is no HTTP client anywhere in the dependency graph, and no code path that
opens a socket. That is not a policy that could drift — it is a property of the
crate graph, and it is worth protecting deliberately. See
[ADR 0002](ADR/0002-local-only-privacy-posture.md).
