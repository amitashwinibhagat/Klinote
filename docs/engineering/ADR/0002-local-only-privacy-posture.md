# ADR 0002 — Local-only as an architectural property, not a policy

- **Status:** Accepted; amended 2026-10-21 (see the note below)
- **Date:** 2026-09-11
- **Deciders:** founder

> **Amendment, 2026-10-21.** Two statements in the original decision are no
> longer literally true, and the product still keeps the promise they were
> protecting. (1) The shell downloads the optional note model once on first use
> (`Sources/Core/ModelDownloader.swift`); that is the app's only outbound
> request. (2) Speech recognition is the system's `SpeechAnalyzer`; Klinote ships
> no speech model and makes no request for it, but macOS may fetch its own speech
> asset once. Audio, transcripts and notes still never leave the Mac. The Rust
> engine remains network-free and the CI denylist is in place.

## Context

The product's reason to exist is that consultation audio and clinical text
never leave the clinician's Mac. Every cloud scribe incumbent is cheaper to
build precisely because it can use a server model, store data centrally and
instrument usage. Our entire differentiation is that we do not.

Privacy that is a *policy* drifts: an analytics SDK gets added, a crash reporter
ships, a model downloads at first run "to improve quality", a cloud fallback
appears behind a flag. Each step looks reasonable in isolation. Together they
destroy the only thing the product has.

## Decision

**Make local-only a structural property of the codebase that a reviewer can
verify mechanically.**

1. No networking code exists in the Rust engine, and no dependency in its graph
   provides an HTTP client. The Swift shell has one named download; the web app
   is a separate surface.
2. The note model is downloaded once, on first use, in one named file. Speech
   recognition is the system's own API; Klinote ships no speech model. No audio,
   transcript or note is ever uploaded.
3. No telemetry, analytics, crash reporting or "anonymous usage statistics" —
   in the app, the shell, or the website's app-facing endpoints.
4. `Encounter::patient_ref` is an opaque pseudonym. Direct identifiers are
   forbidden in the core, in logs, in error messages and in the repository.
5. The audit log is append-only.

## Consequences

**Positive**

- The privacy claim is verifiable by inspection (`cargo tree`, grep for
  `TcpStream`/`http`), not by trust.
- No data-processing agreement is required for a clinic to adopt it, which is
  the core commercial wedge.
- No per-token cost, no usage metering, no rate limits, no outage mode.
- The product works offline, in exam rooms with bad Wi-Fi, and in air-gapped
  environments.

**Negative**

- We cannot ship cloud-model quality for hard cases. Model improvements arrive
  only when Apple updates the OS or we ship new weights.
- No crash telemetry makes remote debugging harder; we rely on local logs the
  clinician can choose to export.
- Support is harder — we cannot look at the data.
- We forgo conventional growth instrumentation. Growth has to be measured
  through conversations and pilots, not dashboards.

## Enforcement

- `cargo tree` is reviewed when adding dependencies. A network client is a
  blocking review failure.
- CI fails on a denylist of networking crates (`.github/workflows/ci.yml`, and
  `scripts/check-network-surface.sh` locally).
- `PatientRef` is a newtype-by-convention; any new field that could carry an
  identifier requires review.
- Template and error strings are included in this repo — they must never
  contain example data that looks like a real identifier.

## Revisit when

Never for the core product. If a cloud-assisted mode is ever considered, it
must be a **separate product** with separate branding, so this one's promise
stays true.
