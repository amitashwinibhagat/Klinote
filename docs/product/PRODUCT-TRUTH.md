# Product Truth — Local Clinical Scribe

Last updated: 2026-09-12 · Verified against: Klinote 0.1.6 (notarized)

This document is the single source of truth for what this product **is**, what
it **does today**, and what may be **claimed externally**. If marketing copy,
a sales conversation or a website contradicts this file, this file wins.

---

## One sentence

Local Clinical Scribe turns a consultation recording into a structured clinical
note entirely on the clinician's Mac, with every statement traceable to what
was said and every draft requiring human review before it enters the record.

## What we may claim today

| Claim | Status | Evidence |
|---|---|---|
| Runs entirely on-device; no network | ✅ true of audio and notes | The Rust engine has no HTTP client (CI). The shell's only network is the first-use download of Quire. Speech recognition makes no request at all — it is the system's `SpeechAnalyzer`. Audio and notes never leave. |
| Produces structured notes from a transcript | ✅ true | `scribe note` on a real transcript, five built-in templates. |
| Notes are traceable to transcript segments | ✅ true | `NoteSection::evidence`; markdown output. |
| Flags missing required sections | ✅ true | `ClinicalNote::missing_required`. |
| Never silently drops transcript content | ✅ true | `unassigned` list + regression test. |
| Supports SOAP, physio, psychology, dental, veterinary structures | ✅ true (structures) | `templates/*.toml`. The *structures* are implemented; clinical validation of each is not. |
| Mac-only | ✅ true by design | Swift shell + Apple platform APIs. |
| Encrypted at rest | ✅ true of the store | SQLCipher, key in Keychain. Not a HIPAA determination. |

## What we must NOT claim today

| Do not claim | Why |
|---|---|
| "Accurate" / "clinically validated" | No clinical evaluation has been performed. Accuracy has been tested on synthetic fixtures only. |
| "Works with your dictation/audio" | Speech recognition is the system's `SpeechAnalyzer` and runs with no download, but a real consult through the *sandboxed* app with a real microphone has not been verified (dev Mac defaulted to BlackHole). |
| "Saves you X minutes per patient" | Not measured on real encounters yet. This is exactly what the validation sprint measures. |
| "HIPAA / GDPR compliant" | Not assessed. Strong privacy *posture* is not a determination. |
| "Integrates with Epic / Cerner / your EHR" | No EHR integration exists. Today the output is Markdown/JSON for copy-paste. |
| "Medical device" / "diagnosis" | This is documentation software. It must not be positioned as clinical decision support. |

## Positioning

Stated in full below; it was recast on 2026-09-12 from a GP framing to a therapy one.

**For** a therapist, psychologist, or psychiatrist in a small room **who**
cannot let a session exist on a vendor's disk **our product** is a local
progress-note draft **that** cites every sentence to words that were said
**unlike** Upheal / Mentalyc / Heidi **because** the audio never leaves the
Mac and the machine is forbidden to invent.

Not for: GPs who are fine with Heidi Free. Not for: anyone whose objection
to a cloud scribe was the editor.

## What the value is, and is not

The model is not the product. Apple ships a capable on-device model for free,
and open models are a download away. The product is:

1. **The template** — the structure a discipline actually documents in.
2. **The routing** — getting the right sentence into the right section.
3. **The completeness check** — telling a clinician what they did not say.
4. **The audit trail** — the ability to answer "why is this in my note?"
5. **The last mile** — getting text into an EHR without breaking the workflow,
   and shipping it with permissions, notarisation and a licence.

## Boundaries

- **In scope:** documentation of a consultation the clinician already conducted.
- **Out of scope:** diagnosis, triage, clinical decision support, patient-facing
  advice, anything that would make this a regulated medical device.
- **Human in the loop, always:** the product drafts; the clinician decides.

## Change log

| Date | Change |
|---|---|
| 2026-09-11 | Initial truth snapshot for engine v0. |
