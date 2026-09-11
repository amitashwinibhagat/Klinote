# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Swift/SwiftUI shell over a Rust core (Cargo workspace in `crates/`), linked as a
static library through a hand-written C ABI. Project generated with XcodeGen.
There is no networking code anywhere in the product; that is an architectural
invariant, not a policy (see `docs/engineering/ADR/0002`).

## Users

Solo and small-practice clinicians in English-speaking markets: general
practitioners, physiotherapists, psychologists, dentists, veterinarians.
Typically one to three practitioners in a practice, Mac users, no IT
department. They document during or immediately after a consultation, usually
with the next patient already waiting.

They will not send consultation audio to a cloud service — either because the
per-clinician subscription costs more than the time it saves, or because their
jurisdiction or their own professional judgement makes the data-processing
agreement the wrong trade.

## Product Purpose

Turn a consultation recording into a structured, template-matched clinical note
draft, entirely on the clinician's Mac. The clinician reviews, corrects and
signs; the machine never signs.

Success is a note the clinician would have written, delivered in less time than
writing it, with the clinician able to see exactly where every sentence came
from. If reviewing the draft takes longer than typing the note, the product has
failed regardless of how good the transcription was.

## Positioning

Not transcription. Transcription is a commodity that Apple now ships for free
in the operating system. The product is the layer above it:

- **the template** — the structure a discipline actually documents in;
- **the routing** — the right sentence in the right section;
- **the completeness check** — telling a clinician what they did not say;
- **the audit trail** — answering "why is this in my note?";
- **the guarantee** — nothing leaves the Mac, so no data-processing agreement
  is required to adopt it.

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
two-speaker turn-taking diarisation. SQLite storage with an append-only audit
log. A C ABI for the shell.

**Not built.** Any UI. A real speech-recognition engine (the shipped default is
a mock that emits synthetic text). A model-backed generator. EHR integration.
Encryption at rest. Retention and deletion.

**Constraints.**

- On-device only. No network code, no telemetry, no runtime model downloads.
- No direct patient identifiers anywhere in the product — `patient_ref` is an
  opaque pseudonym.
- A machine never sets a note to approved. Only a human does.
- Nothing is silently dropped: text that cannot be confidently routed is
  surfaced to the clinician, not discarded.
- Encryption at rest is not yet implemented, so real patient data must not be
  processed by this build.

**Undecided.** Which EHRs to integrate with. Whether the product ships on the
Mac App Store or direct only. Pricing beyond the $99/month validation offer.

## Brand Commitments

**Name: Nota.** From the Latin for a note, and recognisable as "note" across
the Romance languages — a register that is native to clinical language. Short,
calm, and pronounceable in one syllable pair. Internal crate names remain
`scribe-*`; the public name is Nota, the same way the sibling product ships as
WriteAmp over an internal `WriteAmpTyping` identity.

Known consideration: the name sits near "Notability" in the Mac note-taking
category. Accepted for now; the clinical market and the product category are
distinct, and the name was chosen for fit rather than collision-avoidance.

No logo, palette, typeface or voice exists yet. Nothing visual is inherited
from the sibling products (WriteAmp, Echo Flow); this is a separate clinical
brand and must not look like a consumer writing tool.

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
