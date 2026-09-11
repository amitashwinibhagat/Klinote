# AGENTS.md — Local Clinical Scribe

Read this first. It is the durable briefing for any agent or session working in
this repo. Deep detail lives in `docs/`; this file gives the map, the
invariants, the commands, and the gotchas.

## What this is

**On-device ambient clinical documentation for macOS.** A recording goes in; a
structured, template-matched clinical note comes out, with every sentence
traceable to what was said. Nothing leaves the Mac.

- **Engine:** Rust, Cargo workspace under `crates/`. Complete and tested.
- **Shell:** Swift/SwiftUI (next milestone). Calls the Rust core over the C ABI
  in `crates/scribe-ffi/`.
- **Status:** engine v0, no UI yet. Validation is concierge-first — see
  `docs/product/VALIDATION-PLAN.md`.

## THE CONTRACTS (do not weaken, ever)

**1. Local-only.**
There is no networking code in this workspace and there must never be one.
No analytics, no crash reporting, no model downloads at runtime, no telemetry,
no "anonymous usage stats". If a feature seems to need a network call, it is
the wrong feature. This is the product's entire reason to exist.

**2. Traceability.**
Nothing enters a note unless it can be traced to a transcript segment.
`NoteSection::evidence` carries the segment ids. A generator that cannot cite
its source must leave the section empty and let it be reported as missing.

**3. Nothing is silently dropped.**
Text the generator cannot confidently route goes into
`ClinicalNote::unassigned`, not into the bin. An unfiled sentence is a clinical
risk; surfacing it is the point. `never_drops_transcript_content` in
`crates/scribe-note/src/rule_based.rs` is the regression test for this.

**4. A machine never approves a note.**
`ReviewState` starts at `Draft`. Only an explicit human action moves it to
`Edited` or `Approved`. No code path may set `Approved` automatically.
`ClinicalNote::machine_generated` records provenance.

**5. No direct patient identifiers.**
`Encounter::patient_ref` is an opaque pseudonym. No names, MRNs, NHS numbers,
dates of birth, addresses or free-text identifiers anywhere in the core, in
logs, in error messages, or in this repository. The shell owns the mapping and
keeps it out of the Rust side.

**6. Templates are validated, not trusted.**
`Template::validate()` runs on every template, built-in or on disk. A malformed
template is a hard error, never a silent skip — a broken required section means
a clinician signs an incomplete note.

## Commands

```bash
cargo check --workspace --all-targets          # fast feedback
cargo test --workspace                         # 38 tests, no model needed
cargo clippy --workspace --all-targets -- -D warnings   # must stay clean
cargo fmt --all

# Run the engine
cargo run -p scribe-cli -- templates
cargo run -p scribe-cli -- note --transcript fixtures/sample-transcript.txt
cargo run -p scribe-cli -- note --transcript - --db ./scribe.db   # stdin
cargo run -p scribe-cli -- audit --db ./scribe.db --subject <note-id>
```

Nothing in the default build downloads a model or requires one. Keep it that
way: `MockAsrEngine` is the default so CI and the concierge workflow run with
zero setup, and real engines are opt-in.

## Repo layout

| Path | What | Notes |
|---|---|---|
| `crates/scribe-core/` | Domain model: ids, encounter, transcript, template, note | **No I/O, no models, no platform code.** Keep it dependency-light (`serde`, `chrono`, `uuid`, `thiserror`). |
| `crates/scribe-audio/` | WAV ingest, mono downmix, linear resample, energy VAD | `hound` only. No ML. |
| `crates/scribe-asr/` | `AsrEngine` trait + `MockAsrEngine` | Real engines implement the trait; see `docs/engineering/ASR.md`. |
| `crates/scribe-diarize/` | `Diarizer` trait + `TurnTakingDiarizer` | A labelled heuristic. Do not present it as more. |
| `crates/scribe-note/` | `TemplateLibrary` + `RuleBasedGenerator` | Templates embedded via `include_str!` from `templates/`. |
| `crates/scribe-pipeline/` | `ScribePipeline` — the only orchestration point | CLI and FFI both go through here. Do not assemble stages by hand elsewhere. |
| `crates/scribe-store/` | SQLite (rusqlite, bundled) + append-only `audit_log` | JSON blobs for transcripts/notes. |
| `crates/scribe-ffi/` | C ABI, JSON envelopes | `crate-type = ["staticlib","cdylib","rlib"]`. |
| `crates/scribe-cli/` | `scribe` binary | Also the concierge tool. |
| `templates/` | TOML note templates | Add a discipline here, then register it in `TemplateLibrary::BUILTIN`. |
| `fixtures/` | Synthetic transcripts | **Never real patient data.** |
| `docs/product/` | PRODUCT-TRUTH, VALIDATION-PLAN, ROADMAP | |
| `docs/engineering/` | ARCHITECTURE, ASR, ADR/ | |
| `docs/compliance/` | PRIVACY | Encryption-at-rest and retention gaps are tracked here. |

## How to change things

- **Add a template** → write `templates/<id>.toml`, add it to `BUILTIN` in
  `crates/scribe-note/src/templates.rs`, run `cargo test -p scribe-note`
  (`builtins_parse_and_validate` covers every template).
- **Tune routing for a discipline** → edit the `cues` array in the TOML, not
  the Rust. Cues are the clinician-editable surface; the scoring algorithm is
  not.
- **Add a real ASR engine** → implement `AsrEngine`, wire it with
  `ScribePipeline::with_asr`. Do not change the pipeline.
- **Add a model-backed generator** → implement `NoteGenerator`, wire it with
  `ScribePipeline::with_generator`. It must satisfy the traceability and
  no-silent-drop contracts. `RuleBasedGenerator` stays as the no-model fallback.
- **Extend the FFI** → add a function in `crates/scribe-ffi/src/lib.rs`, keep
  the `{"ok":...,"error":...}` envelope, and free strings with
  `scribe_string_free`. When the boundary needs real state (streaming sessions,
  callbacks, model handles), migrate to `uniffi` and delete the JSON envelopes.

## Gotchas

- **Rust 2024 edition:** `#[no_mangle]` must be `#[unsafe(no_mangle)]`, and
  `unsafe fn` bodies are not implicitly unsafe — use explicit `unsafe {}`
  blocks (clippy `not_unsafe_ptr_arg_deref` will catch the missing marker).
- **Paths contain a space** (`Local Clinical Scribe`). Cargo is fine with it;
  third-party build scripts and shell one-liners may not be. Quote paths.
- **`cargo test` must pass without any model, network or audio device.** If a
  test needs a model, it belongs behind a feature flag and off by default.
- **`scribe-store` currently relies on FileVault for encryption at rest.** Do
  not put real patient data through it until SQLCipher + Keychain is wired in
  (`docs/compliance/PRIVACY.md`).
- **`ReviewState::Approved` must never be reachable from generated code.**

## Doc map

| Document | Read it when |
|---|---|
| `docs/product/PRODUCT-TRUTH.md` | You need to know what may and may not be claimed externally. |
| `docs/product/VALIDATION-PLAN.md` | You are doing the 10-clinic concierge sprint. |
| `docs/product/ROADMAP.md` | You are deciding what to build next. |
| `docs/engineering/ARCHITECTURE.md` | You are touching crate boundaries or the Swift boundary. |
| `docs/engineering/ASR.md` | You are wiring a real speech engine. |
| `docs/engineering/ADR/` | You wonder why a decision was made. |
| `docs/compliance/PRIVACY.md` | You are dealing with real patient data. |
