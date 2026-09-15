# AGENTS.md — Local Clinical Scribe

Read this first. It is the durable briefing for any agent or session working in
this repo. Deep detail lives in `docs/`; this file gives the map, the
invariants, the commands, and the gotchas.

## What this is

**Klinote** — on-device ambient clinical documentation for macOS. A recording goes
in; a structured, template-matched clinical note comes out, with every sentence
traceable to what was said. Nothing leaves the Mac.

- **Public name:** Klinote. Internal crate names stay `scribe-*` (the same
  convention as WriteAmp over `WriteAmpTyping`).
- **Engine:** Rust, Cargo workspace under `crates/`. Complete and tested.
- **Shell:** Swift/SwiftUI under `apps/Klinote/`. M1 complete: menu bar, recording
  strip, review window with evidence margin, settings. Builds and launches.
- **Status:** speech recognition is the system's `SpeechAnalyzer` (no model
  download), SQLCipher at rest, Quire on device, sandboxed and notarized. Latest
  release is v0.1.6. Concierge validation is still outstanding, now recast to
  therapists (`docs/product/POSITIONING.md`, `docs/product/VALIDATION-PLAN.md`).

**Design first.** Before changing anything visual, read `PRODUCT.md`,
`DESIGN.md` and `docs/design/UX-PLAN.md`. They are the source of truth; if code
disagrees with `DESIGN.md`, the code is wrong.

## THE CONTRACTS (do not weaken, ever)

**1. Local-only.**
There is no networking code in this workspace and there must never be one.
No analytics, no crash reporting, no telemetry, no "anonymous usage stats". If a
feature seems to need a network call, it is the wrong feature. This is the
product's entire reason to exist.

There is exactly one exception, it is named and it is checked: the Swift shell
downloads the note model once, on first use, in one file —
`Sources/Core/ModelDownloader.swift` — and `scripts/check-network-surface.sh`
fails the build if a second file reaches the network or if anything ever uploads.
**The note model is permanent**, decided 2026-09-15: it is what polishes a draft,
and the app does not try to do without it. So this is not a temporary state to be
engineered away, and nobody should propose removing it without reading
`docs/engineering/LLM-BENCH.md` first. Audio, transcripts and notes never leave
the Mac, before or after the download. An earlier version of this file said
"no model downloads at runtime", which was never true and is now settled the
other way.

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
./scripts/gate.sh                              # fmt, clippy, tests, guards, Swift — the only local "did it work"
./scripts/observe.sh                           # after mutating anything outside the repo; read the output

cargo check --workspace --all-targets          # fast feedback
cargo test --workspace                         # no model needed
cargo clippy --workspace --all-targets -- -D warnings   # must stay clean
cargo fmt --all

# Run the engine
cargo run -p scribe-cli -- templates
cargo run -p scribe-cli -- note --transcript fixtures/sample-transcript.txt
cargo run -p scribe-cli -- note --transcript - --db ./scribe.db   # stdin
cargo run -p scribe-cli -- audit --db ./scribe.db --subject <note-id>

# Build the macOS app (XcodeGen generates the project; do not commit it)
cd apps/Klinote && xcodegen generate
xcodebuild -project apps/Klinote/Klinote.xcodeproj -scheme Klinote \
  -configuration Release -derivedDataPath /tmp/klinote-dd build CODE_SIGNING_ALLOWED=NO
```

The app's build phase compiles the Rust core and links
`libscribe_core_ffi.a` **statically** from `target/klinote-link/`. Never link the
`.dylib`: the linker prefers it, and the bundle then points at an absolute path
in `target/` and cannot run anywhere else.

CI and `cargo test --workspace` must pass with no model, no network and no
audio device. The app downloads Quire on first run into the container; it is not
in the repository or the release zip. Speech recognition has no model at all —
it is the system's `SpeechAnalyzer`, in `Sources/Core/Transcriber.swift`.

## How we know a change worked

A command exiting 0 means the command ran. It does not mean the thing you
wanted happened. In one day that was the entire defect, five times:

1. `echo "clippy clean"` ran unconditionally after clippy.
2. Tests passed against `Readiness` / `CopyGuard` the product never called.
3. `cp` from the wrong directory left a test stub in place and printed nothing.
4. `cargo test | grep passed | awk sum` counted 80 passes while the process
   exited 101.
5. `defaults delete one.klinote.mac` reported success, left the old plist, and
   emptied the sandboxed app's real settings.

Rules, mechanical:

- The only local "did it work" for this repo is `./scripts/gate.sh`. It uses
  exit codes, not greps. Do not invent a counting pipeline beside it.
- After mutating anything outside the repo, run `./scripts/observe.sh` and read
  it before claiming success. It prints the *container* — what the product
  reads — not `~/Library/Preferences`.
- `./scripts/check-wired.sh` (in the gate and in CI) fails if a Domain type
  that Tests mention has no call site in the app.
- After `cp` / `mv` / `rm`, read the destination. After `defaults`, `plutil -p`
  the container plist. Never `echo` success as a separate command.

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
| `apps/Klinote/` | Swift/SwiftUI shell | `project.yml` is the source of truth; the `.xcodeproj` is generated and gitignored. |
| `templates/` | TOML note templates | Add a discipline here, then register it in `TemplateLibrary::BUILTIN`. |
| `fixtures/` | Synthetic transcripts | **Never real patient data.** |
| `docs/design/` | UX-PLAN (shape brief + direction contract) | Read before any UI change. |
| `docs/product/` | PRODUCT-TRUTH, VALIDATION-PLAN, ROADMAP | |
| `docs/engineering/` | ARCHITECTURE, ASR, ADR/ | |
| `docs/compliance/` | PRIVACY | Encryption-at-rest and retention gaps are tracked here. |
| `PRODUCT.md`, `DESIGN.md` | Product truth and the visual system | `DESIGN.md` wins over code. |

## How to change things

- **Add a template** → write `templates/<id>.toml`, add it to `BUILTIN` in
  `crates/scribe-note/src/templates.rs`, run `cargo test -p scribe-note`
  (`builtins_parse_and_validate` covers every template).
- **Tune routing for a discipline** → edit the `cues` array in the TOML, not
  the Rust. Cues are the clinician-editable surface; the scoring algorithm is
  not.
- **Add a real ASR engine** → implement `AsrEngine`, wire it with
  `ScribePipeline::with_asr`. Do not change the pipeline. **The app does not use
  this path:** it recognises in Swift with `SpeechAnalyzer`
  (`apps/Klinote/Sources/Core/Transcriber.swift`) and hands timed segments to
  `ScribePipeline::process_segments`. Whisper is now `scribe-cli` only, and
  nothing in `scribe-ffi` may depend on it.
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
- **The store is SQLCipher, keyed from the Keychain.** Still: no real patient
  identifiers in this repository, in fixtures, or in logs. See
  `docs/compliance/PRIVACY.md`.
- **`ReviewState::Approved` must never be reachable from generated code.** In the
  shell, only the `File note` action (⌘↩) writes it.
- **The app must label synthetic output.** If `MockAsrEngine` or the bundled
  sample produced the draft, the document says so, in `caution`. Do not ship a
  build where a clinician could mistake sample text for a transcription.
- **Never link the Rust dylib.** Xcode's linker prefers it over the static
  library, and the app bundle then depends on an absolute path under `target/`.
  The pre-build script copies the `.a` into `target/klinote-link/` for this reason.
- **After upgrading Xcode, clear the cached build dirs for anything that uses
  cmake** — `llama-cpp-sys-2` and `whisper-rs-sys` here:

  ```bash
  rm -rf target/release/build/llama-cpp-sys-2-* target/release/build/whisper-rs-sys-*
  ```

  Those crates cache an **absolute path to the SDK** in a generated
  `CMakeCache.txt` (`CMAKE_OSX_SYSROOT:PATH=…/MacOSX26.5.sdk`). A new Xcode
  deletes the old SDK directory, so the stale cache hands clang a sysroot that
  no longer exists and every compile fails with:

  ```
  fatal error: 'cstdio' file not found
  fatal error: 'arpa/inet.h' file not found
  ```

  Nothing in that message mentions the SDK, cmake, or Xcode, and a plain
  `clang++ -c` of the same headers succeeds — which is what makes it worth
  writing down. Hit for real going from Xcode 26.6 to 27.0 on 2026-09-15.

## Doc map

| Document | Read it when |
|---|---|
| `PRODUCT.md` | You need product truth: users, positioning, brand commitments, accessibility bar. |
| `DESIGN.md` | You are changing anything visual. It wins over code. |
| `docs/design/UX-PLAN.md` | You are working on a surface: direction contract, states, keyboard map, anti-goals. |
| `docs/product/PRODUCT-TRUTH.md` | You need to know what may and may not be claimed externally. |
| `docs/product/VALIDATION-PLAN.md` | You are doing the 10-clinic concierge sprint. |
| `docs/product/ROADMAP.md` | You are deciding what to build next. |
| `docs/engineering/ARCHITECTURE.md` | You are touching crate boundaries or the Swift boundary. |
| `docs/engineering/ASR.md` | You are wiring a real speech engine. |
| `docs/engineering/ADR/` | You wonder why a decision was made. |
| `docs/compliance/PRIVACY.md` | You are dealing with real patient data. |
