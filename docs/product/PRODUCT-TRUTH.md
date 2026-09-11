# Product Truth — Local Clinical Scribe

Last updated: 2026-09-11 · Verified against: engine v0 (`scribe-cli` 0.0.1)

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
| Runs entirely on-device; no network | ✅ true | No networking code in the workspace. `cargo tree` contains no HTTP client. |
| Produces structured notes from a transcript | ✅ true | `scribe note` on a real transcript, five built-in templates. |
| Notes are traceable to transcript segments | ✅ true | `NoteSection::evidence`; markdown output. |
| Flags missing required sections | ✅ true | `ClinicalNote::missing_required`. |
| Never silently drops transcript content | ✅ true | `unassigned` list + regression test. |
| Supports SOAP, physio, psychology, dental, veterinary structures | ✅ true (structures) | `templates/*.toml`. The *structures* are implemented; clinical validation of each is not. |
| Mac-only | ✅ true by design | Swift shell + Apple platform APIs. |

## What we must NOT claim today

| Do not claim | Why |
|---|---|
| "Accurate" / "clinically validated" | No clinical evaluation has been performed. Accuracy has been tested on synthetic fixtures only. |
| "Works with your dictation/audio" | Real ASR is not wired in. **The default engine is a mock that emits synthetic text.** |
| "Saves you X minutes per patient" | Not measured on real encounters yet. This is exactly what the validation sprint measures. |
| "HIPAA / GDPR compliant" | Not assessed. We have a strong privacy posture; compliance is a separate, legal workstream. |
| "Integrates with Epic / Cerner / your EHR" | No EHR integration exists. Today the output is Markdown/JSON for copy-paste. |
| "Medical device" / "diagnosis" | This is documentation software. It must not be positioned as clinical decision support. |
| "Encrypted" | Data at rest relies on FileVault today. SQLCipher is not wired in. |

## Positioning

**For** solo and small-practice clinicians **who** cannot or will not send
consultation audio to a cloud service **our product** is an on-device ambient
scribe **that** produces a structured, auditable note draft **unlike** cloud
scribes **because** the data never leaves the Mac and there is no per-clinician
subscription to a data-processing agreement.

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
