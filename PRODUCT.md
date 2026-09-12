# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Swift/SwiftUI shell over a Rust core (Cargo workspace in `crates/`), linked as a
static library through a hand-written C ABI. Project generated with XcodeGen.
The Rust engine contains no networking code (see `docs/engineering/ADR/0002`).
The Swift shell's only network action is a first-use download of the open-source
whisper.cpp model; audio and notes never leave the Mac.

## Users

**Primary:** therapists, psychologists, psychiatrists in cash-pay or two-room
practices. Mac already on the desk. The note *is* the record. A session on a
US vendor’s disk is a hard no — ethics, licence, or law.

**Also:** someone who tried Heidi / Mentalyc / Upheal, got an invented finding,
and quit because of the cloud, not the editor. A room where the recording is
not allowed to leave the building (some EU, forensic, high-profile).

**Not:** GPs who are fine with Heidi Free. Dentists, vets, physios as a product
line. Anyone whose objection to a cloud scribe was the editor.

Canonical recast: `docs/product/POSITIONING.md`.

## Product Purpose

Turn a session (recorded, or dictated after) into a progress-note draft the
therapist can stand behind, entirely on their Mac. They review, correct and
sign; the machine never signs, never invents, never silently drops.

Success is a note they would have written, in less time than writing it, every
sentence cited to words that were said. If the draft puts words in the
client’s mouth, or reviewing it takes longer than typing, the product has
failed regardless of how good the transcription was.

## Positioning

> The session stays in the room. The note still gets written.

Not transcription. Not a cheaper Mentalyc. The product is:

- **the room** — audio never leaves the Mac; there is no US vendor in the session;
- **the citation** — every sentence shows the words that produced it; quotes
  that are not in the transcript do not enter the note;
- **the progress note** — DAP / BIRP / their form, not a SOAP dump;
- **the refusal to invent** — no feeling, risk, or finding the client did not name;
- **the last mile** — copy, then paste into the record they already use.

## Operating Context

An examination room. The clinician is sitting with a patient, or has just
finished with one and has three minutes before the next. The Mac is on the desk
and is also running the practice's record system, usually in a browser. Wi-Fi
is unreliable. There is a patient in the room who is aware that a recording may
be happening and whose trust is the whole basis of the encounter.

The clinician's hands are busy. Attention is on the patient, not the screen.
The application is never the thing being looked at during the consultation; it
is looked at afterwards, briefly.

## Capabilities and Constraints

**Confirmed today.** Five note templates (SOAP, physiotherapy, psychology,
dentistry, veterinary) as clinician-editable TOML. Rule-based note generation
with per-sentence evidence links. Required-section completeness checking. A
plain-text transcript path that works with no model at all. WAV ingest, VAD,
whisper.cpp ASR with tinydiarize speaker-boundary detection (model downloaded
once on first use). A Swift/SwiftUI macOS shell: menu bar, patient-visible
recording strip, review window with evidence margin, settings. SQLite storage
with an append-only audit log. A C ABI for the shell.

**Not built.** EHR integration. Retention and deletion.

**Constraints.**

- On-device only. No telemetry. The only inbound network is the first-use
  speech-engine download; audio and notes never leave the Mac.
- No direct patient identifiers anywhere in the product — `patient_ref` is an
  opaque pseudonym.
- A machine never sets a note to approved. Only a human does.
- Nothing is silently dropped: text that cannot be confidently routed is
  surfaced to the clinician, not discarded.
- Notes at rest are SQLCipher-encrypted. The key lives in the Keychain.

**Undecided.** Which EHRs to integrate with. Whether the product ships on the
Mac App Store or direct only. Pricing beyond the $99/month validation offer.

## Brand Commitments

**Name: Klinote.** Clinical + note. Site [klinote.one](https://klinote.one).
The mark is a lowercase sans wordmark — no rule, no serif, no domain line.
Internal crate names remain `scribe-*`; the public name is Klinote, the same
way the sibling product ships as WriteAmp over an internal `WriteAmpTyping`
identity.

Nothing visual is inherited from the sibling products (WriteAmp, Echo Flow);
this is a separate clinical brand and must not look like a consumer writing tool.

## Evidence on Hand

**None.** No design partner, no pilot clinician, no real encounter recordings,
no testimonials, no customer logos, no benchmarks, no outcome data.

No medical, regulatory or compliance claim has been assessed. Nothing in the
product, its interface or its marketing may claim accuracy, clinical validity,
time saved, HIPAA/GDPR compliance, or EHR compatibility until it is measured
and true. See `docs/product/PRODUCT-TRUTH.md`.

## Product Principles

1. **The tool disappears into the task.** This is an Operate surface. Earned
   familiarity beats invention; the clinician should never pause to decode a
   control.
2. **The patient can always see that recording is happening.** Consent is
   visible, not buried.
3. **Every statement is traceable.** Any sentence in a note can be traced to
   the words that produced it.
4. **The machine drafts; the clinician decides.** No generated content is ever
   presented as final.
5. **Keyboard-first and interruptible.** A clinician must be able to record,
   review and sign without touching the mouse, and must be able to stop
   instantly at any moment.

## Accessibility & Inclusion

WCAG 2.2 AA contrast as the floor, on both light and dark appearances. Full
VoiceOver labelling and a coherent focus order on every surface. Respect
Reduce Motion and Reduce Transparency: the recording indicator must remain
unambiguous with all animation and translucency disabled. State is never
communicated by colour alone. The workspace must remain usable at the largest
system text sizes and at high zoom without truncating clinical content.
