# ADR 0002 — Local-only as an architectural property, not a policy

- **Status:** Accepted
- **Date:** 2026-09-11
- **Deciders:** founder

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

1. No networking code exists anywhere in the workspace, and no dependency in
   the graph provides an HTTP client.
2. Models are never downloaded at runtime. A model is either a system API or
   shipped with the app.
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
- CI should fail on a denylist of networking crates (to be added).
- `PatientRef` is a newtype-by-convention; any new field that could carry an
  identifier requires review.
- Template and error strings are included in this repo — they must never
  contain example data that looks like a real identifier.

## Revisit when

Never for the core product. If a cloud-assisted mode is ever considered, it
must be a **separate product** with separate branding, so this one's promise
stays true.
