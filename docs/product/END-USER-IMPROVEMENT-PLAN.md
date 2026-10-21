# End-user improvement plan — Klinote

Status: **Phases 0–5 implemented.** Phase 0 (baseline + contract), Phase 1
(truthful, durable storage), Phase 2 (recoverable capture: encrypted 24-hour
retention via `CaptureVault`) and Phase 3 (resolve content, protect clinician
edits: provenance on the Rust `NoteSentence`, unfiled resolution, move/
exclude/restore, undo) shipped first. Phase 4 (honest output lifecycle)
shipped as: `OutputPolicy` gating copy/print/review on every route with a
refusal sheet that names the fix and jumps to it; an explicit clinician-
authored "Not discussed this session" affordance on empty required sections
(the machine never writes it); a `CopiedReceipt` per encounter so copied and
reviewed are independent facts, with the desk reading receipts instead of
approval state; and revision restamping on human edits so a stale receipt is
detectable. Phase 5 (evidence modes, capture clarity, adaptive layout) shipped as:
`EvidencePresentation` so the margin shows the cited segments for the
selection rather than the whole transcript with a highlight, with explicit
no-selection / clinician-authored / rewritten / missing-source states;
keyboard movement through sentences (↑/↓) and correction (⌘E); an adaptive
review pane that turns the margin into a sheet below 1,000 pt (UX-PLAN §9)
and a lower 720 pt minimum, so the note keeps its measure on a 13-inch Mac
in a half-screen window; the nonfunctional "hide the evidence margin"
setting removed rather than left as a lie; the selected input device shown
and a local level check offered before a first session; and real pipeline
stage names in the strip instead of an invented progress figure. The
validation-gated follow-ups (DAP/BIRP, backup/export, retention refinements)
remain unimplemented, and a manual sandboxed-app pass over Phases 1–5 is
still outstanding.

Scope: the macOS product, not the marketing site. Based on source inspection and
committed screenshots; these are engineering findings and usability hypotheses,
not results of live clinician testing.

## 1. Outcome

A therapist between sessions can capture or enter their account, inspect a
checkable draft, correct it, and copy it into their existing record without
losing work or confusing an unsaved, unreviewed, or incomplete note with a
finished one.

Preserve the incumbent clinical-letter design. This is workflow refinement,
not a redesign, an EHR replacement, or a new AI product.

Priority order:

1. Make storage failures visible and recoverable.
2. Protect capture and transcription from irreversible failure.
3. Make unfiled statements and corrections finishable.
4. Make review and clipboard states truthful.
5. Improve evidence navigation, capture clarity, and small-screen use.
6. Validate before expanding templates or building portability features.

## 2. Non-negotiable boundaries

- Audio, transcripts, and notes never leave the Mac. No telemetry, external
  speech APIs, cloud backups, analytics, or crash uploads.
- Preserve the sole network exception: Quire download in
  `Sources/Core/ModelDownloader.swift`. The note model remains permanent.
- Rust owns clinical routing, grounding, template validation, and pipeline
  orchestration. Do not create a second clinical pipeline in Swift.
- Generated statements retain valid transcript references. Human additions and
  corrections remain explicitly human-originated; never manufacture citations
  or label a clinician's edit machine-verified.
- Unrouted content remains visible until the clinician explicitly resolves it.
  Excluding something from the exported note is not deleting its source.
- Only explicit clinician action approves a particular note revision. Edits or
  redrafts after review invalidate that revision's approval.
- References remain opaque pseudonyms. No patient names or record numbers in
  new metadata, fixtures, logs, errors, or audit details.
- Keep the letter, evidence relationship, visible recording indicator, native
  controls, semantic colours, and reduced-motion/transparency behaviour.
- Do not claim accuracy, compliance, time savings, or EHR compatibility from
  this work. Test data in this repository must be synthetic.

## 3. What exists, and what is actually missing

| Finding | Source | Consequence |
|---|---|---|
| `persist` and encounter deletion swallow store errors | `apps/Klinote/Sources/App/AppModel.swift` | The screen can imply a successful mutation that was not durable. |
| Approval changes the shell's encounter state, while `ClinicalNote.reviewState` is a separate immutable decoded field | `AppModel.swift`, `Domain/Models.swift`, `Core/SessionStore.swift` | Review state needs an end-to-end persistence audit, not just a button-label change. |
| Capture uses a temporary WAV; transcription removes it on both success and error | `Recording/Recorder.swift`, `AppModel.swift` | There is no user-facing retry or durable recovery workflow. Successful recognition alone is not proof that the transcript was saved. |
| Audio write errors are logged, not surfaced to the strip | `Recording/Recorder.swift` | The recording indicator can continue without telling the clinician that capture failed. |
| Unfiled statements have instructions but no resolution controls | `Review/DocumentView.swift` | The clinician cannot perform the action requested by the interface. |
| Generated sentence IDs depend on mutable text | `Domain/Models.swift` | Editing can change identity and complicate selection, undo, and preservation of corrections. |
| Ordinary sentence edits do not acquire the same authored marker used by newly added lines; voice swapping replaces the note | `AppModel.swift`, `Domain/NoteEditing.swift` | Protecting only added lines is insufficient for safe redrafting. |
| Copy is callable despite incomplete sections, and several entry points call it directly | `AppModel.swift`, `App/KlinoteApp.swift`, `Review/DocumentView.swift` | Readiness labels and wrong-session guard logic are not enough unless all output routes enforce them. |
| `uncopied` is inferred from approval rather than clipboard activity | `AppModel.swift` | The home reminder cannot distinguish copied from reviewed. |
| Evidence mode still renders all transcript segments | `Review/MarginView.swift` | The two transcript modes do not provide clearly different jobs. |
| Review uses fixed minimum widths; a settings toggle offers to hide an always-visible margin | `Review/ReviewWindow.swift`, `Settings/SettingsView.swift` | Small-screen behaviour and settings promises need reconciliation. |
| Retention/deletion and template editing already exist | `Settings/SettingsView.swift`, `Core/SessionStore.swift` | Improve these features; do not plan to build them again. |

Additional inspection before implementation: read the complete session-save FFI,
store migration/deletion implementation, and load mapping; verify transaction
boundaries and round-trip behaviour. Some architecture/design documents contain
historical M1 assumptions. Do not treat those as evidence of current behaviour.

## 4. Decisions to approve before coding

### A. Scope versus the existing roadmap

`docs/product/ROADMAP.md` currently prioritises therapist conversations and
permits only requested template-cue fixes. This plan proposes reliability work
beyond that gate. Approve a bounded reliability exception before implementation;
do not silently rewrite the roadmap. DAP/BIRP and substantial recording expansion
remain validation-gated.

### B. Recovery policy

Recommended direction: protected, short-lived local recovery until the next
safe durable checkpoint, not an audio archive. Keep a failed job available for
retry or explicit discard. Remove audio after the transcript and necessary
speaker/timing information are durably saved; drafting can then retry from text.

Approval required for whether failed capture survives quit/relaunch, its maximum
retention period, whether activation is opt-in, and what the clinician sees when
it expires. A 24-hour maximum is a possible pilot policy, not a settled default.
Do not implement retention until this is resolved and documented in PRIVACY.md.

### C. Incomplete output

Recommended direction: prevent normal final-note copying/review when required
sections, including Risk where required, are unresolved. Provide an explicit
clinician-authored "Not discussed" action rather than having the generator
invent it. Any separate incomplete-draft export requires its own approval and
must not look like a completed clinical record.

Grounding failures and missing content take priority over style advice. Ordinary
conversational leftovers and optional wording suggestions should not create a
blocking ritual once the clinician has deliberately resolved them.

### D. Output lifecycle

Recommended direction: track reviewed revision and copied revision separately.
Do not add a mandatory "I pasted it" action initially: Klinote cannot observe
another app's record. If therapists need a handoff checklist, add an optional
self-reported completion state later, clearly labelled as their confirmation.

### E. Smaller screens

Recommended direction: keep evidence visible side by side whenever space allows;
at narrower widths use an immediately accessible source drawer/sheet paired with
the selected sentence. Evidence must remain part of review, not a forgotten
settings toggle. Approve this reconciliation of UX-FLOW's always-present source
with UX-PLAN's adaptive layout before changing either contract.

## 5. Phase 0 — baseline and implementation contract

Deliverables:

- Confirm decisions A–E. Update the relevant portions of PRODUCT.md, DESIGN.md,
  UX-PLAN.md, UX-FLOW.md, ROADMAP.md and PRIVACY.md only where an approved change
  requires it; preserve historical context without rewriting unrelated docs.
- Map every capture, save, edit, review, copy, print, delete, and redraft entry
  point, including global hotkeys, the menu bar, home reminders, and derived
  documents. Record which production path owns each operation.
- Establish baseline synthetic sessions: short dictation, typical therapy
  session, long 50–60 minute session, sparse risk content, unrouted clinical
  material, ordinary conversational leftovers, duplicated lines, and long notes.
- Run `./scripts/gate.sh` and record its actual exit status. Existing failures
  are recorded separately rather than attributed to new code.
- Define the shared state transitions and revision identity before UI work.

Exit criteria: agreed policy, a bounded scope, reproducible baseline scenarios,
and no unresolved choice hidden inside an implementation ticket.

## 6. Phase 1 — truthful, durable storage [P0]

### User experience

- Show an unobtrusive note status: **Saving…**, **Saved on this Mac**, or
  **Not saved — Retry**. Review status is separate from save status.
- Keep failed edits in memory and clearly labelled; do not dismiss an editor or
  navigate away in a way that silently loses the only remaining copy.
- Warn on quit with unsaved work. Offer retry and an explicitly acknowledged
  discard; never pretend the unsaved work is durable.
- Delete only after persistence confirms it. On failure keep the session visible
  and show an actionable explanation. Treat deletion and physical cleanup as
  distinct results if a database delete succeeds but compaction fails.

### Engineering

1. Replace ignored errors with typed results in the production mutation path.
2. Introduce a serial persistence coordinator with per-encounter revisions so an
   older save cannot overwrite a newer edit, approval, or deletion.
3. Make a logical session save atomic: encounter, transcript, note, and required
   audit entries commit together. Derived tasks may be rebuildable, but their
   reconciliation must be explicit and cannot silently erase completion state.
4. Use one canonical persisted review state. Ensure shell status, note JSON,
   store columns, FFI responses, and reload mapping agree.
5. Publish successful approval only after the reviewed revision is committed.
   Failed approval leaves the prior durable state intact.
6. Audit successful actions with opaque IDs/revisions and action types only.
   Never put note text in an audit entry or storage error message.
7. Handle store-lock, unavailable Keychain, disk-full, and malformed-response
   failures without presenting an empty history as a new account.

Primary targets: `App/AppModel.swift`, `Core/SessionStore.swift`,
`Core/KlinoteCore.swift`, `Domain/Models.swift`, `Domain/Encounter.swift`,
`Review/ReviewWindow.swift`, `crates/scribe-store/src/lib.rs`, and session-save
functions in `crates/scribe-ffi/src/lib.rs` plus its C header.

Acceptance:

- Force a write failure while editing: text remains recoverable, status says
  not saved, and retry persists exactly the latest revision.
- Force a delete failure: the row remains; there is no false deletion receipt.
- Save, review, quit, reopen: the exact content and review state round-trip.
- Rapid saves followed by deletion cannot resurrect the session.
- Atomic-save failure leaves neither a partial session nor a success audit.
- A reviewed note changed by edit/redraft becomes unreviewed and stays so after
  reopening. No automatic path sets it approved.

## 7. Phase 2 — recoverable capture and transcription [P0]

Depends on Phase 1 and approved recovery policy.

### User experience

- Distinguish **Recording**, **Transcribing**, **Writing draft**, **Saving**, and
  **Could not finish**. State what is safe and what can be retried.
- On failure offer the relevant next action: **Retry transcription**, **Retry
  writing**, **Retry saving**, or **Discard capture**, rather than "record again".
- After restart, show recoverable jobs with pseudonym, time, stage, expiry, and
  a brief preview only when protected source text is available.
- A capture error interrupts the liveness claim immediately and states the
  last confirmed captured point. Never claim the full session was recorded.

### Engineering

1. Run a bounded security/feasibility spike for encrypted recovery. Sandboxing
   and a normal temporary WAV are not equivalent to encrypted storage.
2. Evaluate authenticated encrypted chunks with atomic metadata/checkpoints,
   a Keychain-held key, and bounded storage. Keep live capture ownership in
   Swift; do not introduce stateful C handles just to retain jobs. If such
   handles genuinely become necessary, follow the documented uniffi migration
   rule rather than growing the JSON ABI into a session protocol.
3. Define the unavoidable transient decode/WAV requirements of SpeechAnalyzer
   and the Rust VAD path. Minimise their lifetime, document crash cleanup, and
   do not promise physical secure erasure on SSDs.
4. Give each job a stable ID and persist its stage/checkpoints independently of
   whether a note exists. Reuse that identity on retry; no duplicate encounters.
5. Checkpoint recognised timed segments before note drafting. Persist complete
   transcript/role mapping before retiring audio needed for diarisation.
6. Resume from the last successful stage. A drafting failure must not repeat
   successful recognition; a save failure must not discard the source.
7. Make cancellation, deletion, recovery expiry, and background completion
   cooperate. Late tasks cannot revive discarded jobs or overwrite newer notes.
8. Surface write errors, interruption/device loss, and insufficient storage.
   Chunk processing must not block the realtime audio callback.
9. Guard quit during active capture and test forced termination separately.

Primary targets: `Recording/Recorder.swift`, `Recording/RecordingStrip.swift`,
`Core/Transcriber.swift`, `App/AppModel.swift`, `Core/SessionStore.swift`,
new production capture/recovery coordinator, and a durable recovery-job store.

Acceptance:

- Transcription failure leaves a protected retryable source under the approved
  policy; retry produces one encounter with valid evidence.
- Note-generation failure preserves the transcript and supports retry without
  a second microphone session.
- Save failure after successful recognition does not destroy the last durable
  recoverable source.
- Restart/forced termination recovers only confirmed checkpoints, accurately
  labels any lost tail, and handles partially written chunks safely.
- Corrupt recovery files fail closed without exposing plaintext in errors.
- Expiry/discard removes recovery records and files; verify the actual storage,
  not just disappearance from the UI.
- A long synthetic session has bounded memory/storage and responsive controls.

Shipping gate: do not enable durable audio retention before the encryption,
cleanup, consent wording, and retention tests are complete. Do not substitute
an indefinitely retained plaintext WAV to make retry appear implemented.

## 8. Phase 3 — resolve content and protect clinician edits [P1]

### User experience

For each unfiled statement:

- **Move to section…** with the destination headings.
- **Exclude from note** with a reversible resolution, not destruction of source.
- **Show source** using its original evidence references.

For note editing:

- Keep precise sentence correction, but expose **Edit** without requiring users
  to discover double-click.
- Add **Move to section**, reversible **Remove from note**, and undo/redo.
- Add **Edit section** only with explicit provenance behaviour: unchanged lines
  retain their citations; changed/new text is marked as clinician-authored or
  clinician-edited, not assigned guessed citations.
- Before redrafting or swapping voices, make it clear that a new draft will be
  produced. Preserve corrections and exclusions, and offer comparison before
  replacement when the mapping is ambiguous.

### Engineering

1. Introduce stable sentence and unfiled-item identity independent of text.
   Decode legacy notes with safe defaults and persist IDs on first mutation.
2. Define explicit provenance for generated, corrected, and newly authored text.
   Source links on corrected lines mean "original source", not re-verification
   of the new wording. Preserve both facts in the margin.
3. Centralise add/edit/move/exclude/restore transformations in production-used
   operations. Rebuild section bodies, section evidence, completeness, source
   flags, review invalidation, and task reconciliation consistently.
4. Persist unfiled resolution metadata, scoped to source and revision. A redraft
   must not silently revive exclusions or lose intentionally moved content.
5. Route updated machine-generated content through the existing grounding
   checks. Human edits clear obsolete machine verdicts, never invent a pass.
6. Use a per-encounter undo history for note operations. Undo changes content,
   not the append-only audit history, and does not automatically reapprove.
7. Preserve authored lines AND corrections through all redraft paths, including
   voice swapping and model-download completion. Guard against stale jobs and
   concurrent edits with expected revisions.
8. If arbitrary paragraph edits cannot be mapped safely, mark the changed
   passage clinician-originated and preserve the previous revision for recovery;
   do not pretend that free-text rewriting preserves sentence-level evidence.

Primary targets: `Domain/NoteEditing.swift`, `Domain/Models.swift`,
`App/AppModel.swift`, `Review/DocumentView.swift`, `Review/MarginView.swift`,
Rust note serialisation/validation and the existing store/FFI boundary.

Acceptance:

- Move an unfiled statement: it appears in the selected section, copy output
  contains it once, and its original evidence remains selectable.
- Exclude and undo: source survives, the decision persists across restart, and
  export includes only the deliberately selected note content.
- Two identical statements can be selected, moved, and undone independently.
- Required-section completeness recalculates after removing/moving its last line.
- Add a line, correct a generated sentence, exclude an item, then redraft/swap:
  none of those human decisions silently disappear.
- Edit during a background redraft: the late result cannot overwrite the edit.
- Section editing never attributes new clinical statements to the client.

## 9. Phase 4 — honest review and output lifecycle [P1]

Depends on Phases 1 and 3.

### State model

Keep four concepts independent:

| Concept | Meaning |
|---|---|
| Save state | Whether this exact revision is durably stored. |
| Completeness/checks | Required sections and unresolved source/content checks. |
| Review state | Explicit clinician approval of this exact revision. |
| Clipboard state | Last revision successfully placed on the clipboard. |

Legacy notes must not be labelled copied merely because they were approved.
Represent unknown historical clipboard state honestly.

### Work

1. Create one shared output coordinator for toolbar, signature block, menus,
   global shortcuts, earlier-session actions, print, and derived documents.
2. Verify the intended session, revision, visible context, and readiness before
   output. Retain wrong-session confirmation where needed.
3. Apply the approved incomplete-output policy. Name missing sections and take
   the clinician directly to the relevant editor or source.
4. Treat an empty required Risk section as unresolved; a human may explicitly
   document that it was not discussed. Never suggest a clinical finding merely
   to pass the completeness check.
5. Check the actual clipboard write result. Record copied revision/time only
   after success, and distinguish failure to persist that receipt from failure
   to place text on the clipboard.
6. Update the desk reminder from real copy/review facts, not the current
   `state != approved` inference. Editing makes an older copy visibly stale.
7. Keep receipts brief: "Copied this revision. Paste into your record." Never
   report successful paste or record delivery without explicit human reporting.
8. Scope review shortcuts to context: Command-Return saves an active edit or
   marks the note reviewed, never both. Print obeys the same content guards.

Acceptance:

- An incomplete or source-unresolved note cannot bypass the policy through a
  global shortcut or alternate menu.
- Copying a different or hidden session requires the appropriate context check.
- A copied draft remains unreviewed until the clinician explicitly reviews it.
- Editing after copy shows that the clipboard receipt refers to an older revision.
- Copy success, review success, and saving success remain distinct after restart.
- No path claims that the note reached the external record automatically.

## 10. Phase 5 — evidence, capture clarity, accessibility [P2]

### Evidence

- Evidence mode shows the selected sentence's cited segments first, with optional
  nearby context. Full transcript mode shows the full searchable session.
- Provide explicit selected-source, no-selection, clinician-authored, and
  ambiguous-source states. Do not manufacture phrase-level precision if only
  segment-level support exists.
- Use clear labels such as **Full transcript**, accessible source navigation,
  and keyboard movement between note sentences and their evidence.
- Keep source positions stable while editing and undoing. Avoid scrolling that
  fights the clinician or ignores Reduce Motion.

### Capture

- Before first recording, show the actual selected input and offer a short
  local level test. A level test confirms signal, not transcription accuracy.
- Add an input chooser only if the sandboxed capture path can support it
  reliably; otherwise show the system input with an actionable explanation.
- Resolve Pause/Hold terminology in a single concept: either one pause action
  with recorded gap metadata or clearly differentiated consequences. Preserve
  immediate stop and client-visible recording state.
- Explain microphone permission, speech capability/assets, model writing, and
  local storage separately. Keep sample, dictate, and paste routes first-class.
- Display real processing stages and elapsed wait. Do not fabricate percentages
  for recognition or generation that expose no measurable progress.

### Layout and accessibility

- Test a 13-inch Mac, constrained half-screen windows, long notes, increased
  text size, dark/light appearance, increased contrast, VoiceOver, Reduce Motion,
  and Reduce Transparency.
- Implement the approved adaptive source layout; do not shrink clinical text
  to preserve a fixed-width composition.
- Remove or reconcile the nonfunctional margin-visibility setting.
- Add discoverable edit/navigation actions, consistent focus order, and clear
  accessible descriptions of flags and source relationships.
- Keep clinically meaningful text wrapping rather than truncating it.

Acceptance: a keyboard-only clinician can enter text, inspect sources, resolve
an item, correct content, review, and copy without a mouse. Source access remains
obvious in the smallest supported review window. The recording indicator remains
unambiguous with motion/transparency disabled.

## 11. Validation-gated follow-ups [not in the first reliability release]

### Therapy templates

Trigger: a paying therapist names the note shape they need, consistent with the
existing roadmap. Add DAP/BIRP only then; keep the current template available for
existing users. Do not force a different template onto historical notes.

- Preview the actual headings and required flags before selection.
- Add validated TOML templates, register them in TemplateLibrary, and keep
  routing cues in TOML rather than hardcoding them into Rust.
- Use approved language for required Risk documentation without fabricating it.
- Test completeness, routing, evidence, no silent drops, and copy output on
  synthetic discipline-specific examples; clinically validate separately.
- Make simple writing preferences understandable; leave advanced routing and
  model instructions under an advanced editor.

### Local backup and export

Trigger: clinicians confirm Klinote is retaining material they need to recover
or move. This is a separate security/portability project, not "copy the DB".

- Decide whether the external record or Klinote is authoritative.
- Design a documented encrypted backup format with a portable recovery secret;
  a database copied without its Mac-local Keychain key is not a usable backup.
- Export/restore through a user-selected destination using sandbox-supported
  file access. No automatic sync or network calls. Explain that a user-selected
  folder could itself be synced by another application; do not claim control
  over that other app.
- Include source/evidence, revisions, resolutions, templates, and nonclinical
  metadata as appropriate. Never log clinical content or secrets.
- Test restore on a fresh synthetic installation with no original Keychain
  entry, not only on the originating Mac.

### Retention safeguards

Retention already exists. Improve it with a preview of affected sessions before
changing to a destructive policy, confirmation for manual deletion, actual error
reporting, and a reminder to follow applicable professional rules. Do not choose
legal retention requirements on the clinician's behalf.

## 12. Test strategy — production paths, not parallel test-only logic

The current Swift test target compiles Domain files, not AppModel or the live
coordinators. It is useful but cannot prove that persistence/recovery/output are
wired correctly. Avoid repeating the tested-but-unused-domain failure.

- Extract production-used coordinators behind injected capture, store, clock,
  drafting, and clipboard interfaces. Compile those exact source files into a
  headless test target; update `apps/Klinote/project.yml` accordingly.
- Keep unit tests free of Keychain prompts, real microphone requirements,
  downloads, and model dependencies.
- Add integration tests through the actual C ABI with an isolated synthetic
  database and test-owned encryption key. Verify round-trips, failures,
  migrations, review state, resolutions, and deletion results.
- Test migration from legacy notes without IDs/resolution/copy metadata and
  legacy databases. A future schema version must fail safely rather than be
  silently treated as compatible. No destructive production-data migration.
- Add fault injection for storage errors, partial capture, transcription/draft
  failure, corrupt recovery, expired jobs, clipboard failure, stale background
  completions, rapid saves, concurrent edits, and quit/restart.
- Run sandboxed smoke tests on the actual product with synthetic recordings,
  including a physical microphone and device interruption. System-loopback
  success is not proof of a real microphone workflow.
- `./scripts/check-wired.sh` is necessary but only checks source mentions. Verify
  that every production entry point reaches the coordinator; do not treat a
  passing wiring scan as proof of behavioural routing.

Required behavioural scenarios:

| Scenario | Proof required |
|---|---|
| Type/paste → edit → save → reopen | Stored note exactly matches the displayed revision. |
| Dictate → transcription failure → retry | Protected recovery survives and produces one note. |
| Record → successful recognition → draft failure | Transcript survives; retry starts at drafting. |
| Review → save failure | No false approval; prior durable state remains. |
| Unfiled → move/exclude → undo → reopen | Content/source/resolution round-trip without loss. |
| Edit → redraft/swap while editing | Human corrections survive; stale jobs cannot replace them. |
| Copy via each UI/global route | Same readiness and wrong-session policy everywhere. |
| Delete/expire → restart | No resurrection; verify files/database, not just list state. |
| Legacy migration → edit/review/copy | Safe defaults; no invented historical completion. |
| Long session / small display / VoiceOver | Responsive controls and a finishable review workflow. |

After implementation, the only local overall code gate is `./scripts/gate.sh`.
Read its exit status; do not count grepped test output. After mutating anything
outside the repo during sandbox verification, run `./scripts/observe.sh` and
inspect what the product actually reads. Verify deletion, retention, and save
outcomes at the destination. A success status or visible banner is not proof.

## 13. Delivery sequence and release gates

Suggested increments, not calendar promises:

1. **Contract and baseline:** approve policies; establish fixtures and failure
   cases; confirm migrations and test seams.
2. **Reliability A:** durable saves/deletes/review-state round-trip and production
   coordinator tests. Ship only when failure messages are truthful.
3. **Reliability B:** protected recovery, staged retry, capture failure signalling,
   and sandboxed restart verification. Ship only after privacy policy approval.
4. **Finishable review:** stable provenance/IDs, unfiled resolution, reversible
   corrections, redraft protection, and consistent output guards.
5. **Usability refinement:** evidence modes, keyboard navigation, capture clarity,
   and adaptive layout, verified in one batched visual/accessibility pass and a
   single confirmation pass after corrections.
6. **Validation-led expansion:** named template asks, retention refinements, and
   backup/export as separately approved work.

Use small coherent changes; avoid combining capture format, store migration,
editor redesign, and new templates into one release. Optional capabilities can
be staged, but do not hide reliability requirements behind experimental toggles.
Before any schema-changing release, verify restore/migration on synthetic data;
never assume a downgrade can safely read the new schema.

## 14. Clinician validation and stop conditions

Start with 3–5 therapists using synthetic scenarios. Test each capture route,
including people who refuse ambient recording. Keep observations local and
manual; no analytics SDK or collection of actual clinical content.

Observe:

- Can they tell whether the note is saved, reviewed, and copied?
- Can they recover from a failure without recreating the session?
- Can they resolve unfiled clinical material without bypassing it?
- Can they correct a paragraph and still explain its provenance?
- Can they identify a wrong-session output and an unsupported statement?
- Does the chosen template match the form they already use?
- Does review take less effort than their own typing workflow? Measure locally;
  do not convert an early observation into an external time-savings claim.

Record task completion, errors, unnecessary steps, and user explanations. Define
usability thresholds from the baseline rather than inventing a universal
90-second promise. Real-session validation requires the existing privacy,
consent, and professional-policy prerequisites; this plan does not waive them.

Stop/re-scope if recovery requires weakening privacy, clinicians still cannot
finish safely, or review takes longer than their existing workflow. If users
choose dictate/paste rather than recording, prioritise those paths rather than
expanding ambient capture by default.

## 15. Approval checklist

- [x] Approve a bounded reliability exception to the current validation-first roadmap.
- [x] Approve recovery encryption/lifetime/activation and failure-expiry behaviour —
      implemented as AES-GCM in the sandboxed support directory, 24-hour expiry at
      launch and at every refresh, automatic activation on failure.
- [x] Approve incomplete-copy/review policy, including explicit Risk handling —
      implemented as `OutputPolicy` on every output route, with the refusal
      naming the fix, and "Not discussed this session" as a clinician-authored
      line only.
- [x] Approve independent review/copy revision states without mandatory paste
      confirmation — implemented as per-encounter `CopiedReceipt`s compared
      against the revision stamp; no paste confirmation exists.
- [ ] Approve adaptive source access on smaller screens. *(Phase 5)*
- [ ] Keep DAP/BIRP, full section rewriting, and backup/export gated where their
      clinical/provenance/security decisions remain unresolved.

Next action: the manual sandboxed-app pass over Phases 1–5 (real microphone,
forced failures, 13-inch window, VoiceOver) before any further code, then the
validation-led work gated on paying therapists.
