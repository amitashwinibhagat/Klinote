# Roadmap

Ordering principle: **ship the smallest thing that could earn a paying
clinician, then let the evidence decide the next step.** Engine before UI,
because the engine is what the concierge test exercises; real models before the
shell, because model quality is the thing most likely to kill the product.

---

## Now — engine v0 (done)

- [x] Cargo workspace, domain model, template engine
- [x] Rule-based generator with evidence links and completeness check
- [x] Plain-text transcript parsing (roles, timestamps, wrapped lines)
- [x] WAV ingest, VAD, two-speaker turn-taking diarisation
- [x] SQLite store with append-only audit trail
- [x] C ABI for the Swift shell
- [x] `scribe` CLI — the concierge tool
- [x] 38 tests, clippy clean, no model or network required

## Next — validate (2–4 weeks, no new code required)

From `docs/product/VALIDATION-PLAN.md`:

- [ ] 10 clinician conversations
- [ ] 5 clinicians × 5 real encounters delivered by hand
- [ ] Record edit distance, routing errors, missing sections, $99 answers
- [ ] Tune template cues — the only permitted code change

**Gate: 3 paying clinicians before any of the following is built.**

## Next — make it real (4–6 weeks, only after the gate)

1. **Wire a real ASR engine.** `SpeechAnalyzer` in the Swift shell is preferred
   (free, streaming, no model download, no notarisation constraint). Whisper or
   Parakeet in Rust is the portable fallback. See `docs/engineering/ASR.md`.
2. **Speaker role correction.** Diarisation will mis-assign roles. One-click
   "this was the patient" in the shell, feeding back into the pipeline.
3. **Encryption at rest.** SQLCipher + Keychain before real data. Non-negotiable.
4. **Retention and deletion.** Per-practice policy, real delete, vacuum.
5. **Swift shell, minimum viable:** menu bar, record/stop, role correction,
   note review + edit, copy to clipboard. No EHR integration yet.

## Later — only with evidence

| Item | Trigger |
|---|---|
| Model-backed generator (AFM 3 via Foundation Models) | Rule-based routing accuracy plateaus below the edit-distance target |
| Specialty templates beyond the five | A paying discipline asks and the cue work is reusable |
| EHR integration (paste automation, then FHIR/API) | ≥ 5 paying clinicians name the same EHR |
| Site licence / multi-clinician practice | A practice asks for it |
| Windows shell (same Rust core, Tauri or native) | A paying clinic is Windows-only |
| Practice-pack vocabulary (drug names, procedure codes) | Accuracy on real encounters is limited by vocabulary |

## Explicitly not planned

- Cloud anything. This is the product's identity.
- Diagnosis, coding suggestions, or clinical decision support — different
  regulatory category, different company.
- A consumer "transcribe my meetings" mode. Adjacent, but it dilutes the
  clinical position and invites competition with free OS features.
- Mobile capture app. The Mac is where the documentation happens.

## Risks being tracked

| Risk | Mitigation |
|---|---|
| Apple ships clinical documentation | Very unlikely; Apple avoids regulated verticals. |
| Apple's on-device dictation makes generic transcription free | Already priced in — the product is the template, routing and audit trail. |
| Diarisation accuracy in a real exam room | Role correction UI; measure it during the sprint. |
| Clinicians won't record patients | Measured in the sprint — structural objection, needs an answer before building. |
| Model licensing for bundled weights | Prefer Apple system models; audit any bundled weights. |
