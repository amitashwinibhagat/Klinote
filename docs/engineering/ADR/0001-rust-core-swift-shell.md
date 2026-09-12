# ADR 0001 — Rust core with a native Swift shell

- **Status:** Accepted
- **Date:** 2026-09-11
- **Deciders:** founder

## Context

We are building an on-device ambient clinical scribe for macOS. The product
needs two very different kinds of code:

1. **Engine work** — audio DSP, VAD, ASR orchestration, diarisation, template
   rendering, note assembly, storage, audit. Hot, algorithmic, highly testable,
   and desirable on other platforms later.
2. **Platform work** — microphone capture, on-device speech recognition
   (`SpeechAnalyzer`, macOS 26+), the on-device foundation model
   (`FoundationModels` / AFM 3), Accessibility-based text insertion into an EHR,
   the menu bar, Keychain, notarisation and StoreKit.

The founding question was whether to build the whole app in Rust (Tauri or a
pure-Rust GUI) or in Swift.

**The constraint that decides it:** Apple's two best on-device primitives —
`SpeechAnalyzer` and `FoundationModels` — are **Swift-only APIs**.
`FoundationModels` in particular is not Objective-C-exposed, so a pure-Rust app
cannot use it without writing a Swift bridge, at which point Swift is already in
the project. A Rust-only app therefore either gives up the free, best-in-class
Apple models or writes Swift anyway.

## Decision

**Split the system at a deliberate seam: a portable Rust core, driven by a
native Swift shell.**

- The Rust core owns everything hot, portable and testable, and has no
  knowledge of macOS.
- The Swift shell owns everything that is genuinely macOS and calls into the
  core over a C ABI.
- Interop starts as a hand-written C ABI with JSON envelopes
  (`crates/scribe-ffi`), and migrates to `uniffi` when the boundary needs real
  state (streaming sessions, callbacks, model handles).

## Consequences

**Positive**

- Direct access to `SpeechAnalyzer` and AFM 3 — free, fast, private, and with
  no model weights to ship.
- Reuse of the last mile already solved in a sibling product: notarisation,
  DMG/MAS distribution, StoreKit and direct licensing, the app-compatibility
  work, and the release pipeline.
- Engine logic is unit-testable with no model, no audio hardware and no network,
  so CI is fast and deterministic.
- The same core can back a future Windows shell or a batch/CLI product without
  a rewrite.
- Tauri's WebView is kept away from a clinical app: no extra RAM competing with
  a local model on a 16 GB Mac, and a smaller audit surface.

**Negative**

- Two languages and two build systems, plus an FFI boundary to maintain.
- The C ABI adds boilerplate and manual memory management for returned strings.
- macOS-first: a Windows shell is a separate piece of work later.
- The repo path contains a space, which some third-party build scripts dislike.

## Alternatives considered

**Tauri (Rust backend + web UI).** Rejected for the capture app: WebView memory
competes with a local model on 16 GB machines, macOS integration (global
hotkeys, Accessibility insertion, camera/mic under a hardened runtime) needs
native plugins regardless, and it still cannot reach `FoundationModels` without
a Swift bridge. Tauri remains the right choice for the clinic-facing **review
console** and a possible Windows shell, both reusing this same Rust core.

**Pure Rust GUI (egui/iced).** Rejected: same Apple-framework problem, weaker
macOS integration, and more UI work for a worse result in a product where
clinician trust depends on native polish.

**All-Swift app.** Simplest path and the strongest Apple integration, but loses
engine portability, expressiveness and testability, and couples every algorithm
to the platform. The Rust core is the part most likely to outlive the macOS
app.

## Revisit when

- The FFI boundary grows state or callbacks (migrate to `uniffi`).
- A paying clinic is Windows-only (build the Windows shell on the same core).
- Apple exposes `FoundationModels` to Rust via a supported interface.
