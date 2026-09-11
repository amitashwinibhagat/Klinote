# UX Plan — Nota

**Shape brief + direction contract.** Surface: the macOS app shell and its first
authoritative surface, the note review window.

Status: code-led build (no image generation in this harness → the comp round is
skipped by contract, not by drift). Ambition is carried by the direction
contract below.

- Product truth: `PRODUCT.md`
- Visual system: `DESIGN.md`
- Engine: `README.md`, `docs/engineering/ARCHITECTURE.md`

---

## 1. The direction roll

Run against the Impeccable catalog. Required on a new visual world; it exists so
that every run does not converge on the same category default.

- **Seed key:** `4a273941`
- **Assigned:** candidate **4** of my own grounded list (below)
- **Chose:** candidate 4, built as presented.

### My grounded list, ordered by resonance

Seven visual systems drawn from the audience's own world — clinical
documentation's graphic and screen traditions — each joined to a concrete
first-surface expression.

| # | Direction | Material world | First surface |
|---|---|---|---|
| 1 | **The Dictaphone** | Olive-grey transport, tactile rocker keys, tape counter, single red record lamp | The recording strip: a mechanical deck you can trust at a glance |
| 2 | **The reading room (PACS lightbox)** | Dark room, greyscale plates on black, measurement rules, cine transport | Evidence review: note and source side by side in a darkened field |
| 3 | **The observation chart** | Ruled graph paper, plotted series, early-warning colour bands, plotted-in-ink conventions | The trend/measurement blocks inside the note |
| 4 | → **The clinical letter** | Letterhead block, ruled field grid, small-caps field labels, marginal annotations, signature and countersignature rules, a filed stamp | **The note itself as a working document**, with evidence in the margin |
| 5 | **The kardex** | Dense ruled time grid, initial boxes, drug rows | The completeness and medication blocks |
| 6 | **The theatre checklist** | Pause points, read-aloud rhythm, tick columns | Consent and recording ritual |
| 7 | **The specimen label** | Small caps, technical codes, stable identifiers | The audit trail |

Candidate 4 is the honest fourth choice: the more resonant worlds (the
machine that listens, the room where evidence is read) are stronger *stories*,
but they are surfaces, not durable systems. The clinical letter is the only one
of the seven that can carry navigation, quiet and dense content, every
interaction state, and a substantially different future surface without
breaking. That is what the assignment is selecting for.

### Challengers weighed

Each fused with the product's facts before judging — challenger supplies the
form, Nota supplies the content, clarity wins conflicts.

| Challenger | Audience identification | Product clarity | Verdict | Kept line (raise) |
|---|---|---|---|---|
| Split-flap departure board | ✗ airport, not clinic | ✗ motion is the content | **Declined** | Rows restyle per state **without breaking the grid** → encounter rows keep ruled columns while status changes |
| Darkroom exposure record | ✗ darkroom | ~ tonal rigour reads as precision | **Declined** | Overlapping translucent annotation carrying a **numeric delta** → margin evidence marks carry source index and offset |
| Character-goods catalog | ✗ | ✗ wrong register entirely | **Declined** | Whole-cell roster reflow → encounters list reflows in whole rows, never partial |
| Japanese high-density web | ~ dense charts are how clinicians read | ✓ packs real information | **Competitive** | Hairline module mosaic with **small header tabs** → note sections are ruled modules, packed without whitespace inflation |
| Cloud quarry | ✗ surreal | ✗ | **Declined** | Deep voids between stacked blocks → vertical rhythm between note sections |
| Drawcord transforming cape | ✗ | ✓ one gesture materialises structure | **Declined** | **One deliberate pull turns a flat plane into structure** → "Assemble" turns raw transcript into the ruled letter in one motion |
| Oscilloscope on a signal bench | ~ clinicians read traces all day | ✓ persistent trace on a graticule | **Competitive** | Graticule + persistent trace → the recording strip's waveform |
| Sneaker archive wall | ✗ | ✓ end-label index discipline | **Declined** | End-label index grid → encounter rows as labelled spines |

No challenger won both axes. The assigned direction stands, raised by six named
donations. The two competitive challengers (Japanese high-density,
oscilloscope) remain available as full alternates if the build stalls.

### The assigned direction, raised

**The clinical letter.** A note is a formal document addressed to the record:
letterhead, ruled field grid, structure, marginal annotation, a signature, and
a filing stamp. Nota treats the generated note as that document — and puts the
evidence in the margin, where a careful reader has always put it.

Raises carried in, each named for its donor:

- **Grid discipline (split-flap):** encounter rows hold their ruled columns
  while their state changes beneath them.
- **Numeric marginalia (darkroom):** every note sentence carries a margin mark
  with its source index — a number, not a colour.
- **Module mosaic (Japanese high-density):** note sections are hairline-ruled
  modules with small-caps header tabs, packed edge to edge; no whitespace
  inflation.
- **One gesture (cape):** a single **Assemble** action turns the raw transcript
  into the ruled letter.
- **Persistent trace (oscilloscope):** the recording strip draws a live trace
  on a graticule; it does not decorate, it reports.
- **End-label index (sneaker archive):** the encounter list reads as labelled
  spines — pseudonym, time, discipline, state.

## 2. Direction contract

> Development-only. Never copied into app source, comments, or shipped assets.

**THESIS.** The note is a document addressed to the record, not a form filled
in on screen; evidence lives in the margin. Refuses the category default of a
chat transcript beside a coloured card of "AI summary".

**OWN-WORLD.** Ruled letterhead grid; hairline section modules with small-caps
header tabs; document body in New York (Apple's serif); interface in SF Pro;
timestamps and identifiers in SF Mono tabular; two-tone ground — desk chrome
against a raised document plane; one ink accent for the letterhead rule and
primary action; record red reserved solely for the act of recording; amber
solely for a missing required section. Recognisable with all content removed:
rules, tabs, margin column, signature block.

**STORY.** The clinician understands *this is my note, already drafted*, sees
immediately what is missing, can trace any sentence to what was said, and files
it. Trust comes from being able to check, not from being asked to believe.

**FIRST VIEWPORT.** A single window, three regions under one toolbar: encounters
as labelled spines at left (~260 pt); the note as a ruled document, centred,
at a 68-character measure; a margin column at right (~320 pt) carrying source
utterances. The letterhead block sits at the top of the document — practice,
discipline, date, encounter reference, engine provenance. The primary action,
**File note**, sits in the document's own signature block at the foot, not in
the toolbar. At 1280 pt the margin collapses to marks only; the document never
narrows below its measure.

**FORM.** The clinical letter (candidate 4 of 7, ordered by resonance). Seed key
`4a273941`.

**FINISH.** unreviewed and undocumented is unfinished; this build ends with the
finish review, the verdict, DESIGN.md, and every shipping raster carrying its
provenance.

## 3. Job and audience

| | |
|---|---|
| **Who arrives** | A clinician who has just finished a consultation, with three minutes before the next patient. |
| **Mode** | Operate. The tool disappears into the task. |
| **Job** | Confirm or correct a draft note and file it — faster than typing it would have taken. |
| **State of mind** | Time-pressured, accountable, mildly sceptical of machine output, and legally responsible for what they sign. |
| **Success** | The clinician files the note in under 90 seconds of editing, and can point at any sentence and say why it is there. |
| **Failure** | Reviewing takes longer than typing. A wrong sentence is filed because checking it was harder than trusting it. |

## 4. Outcome and proof

**Primary task:** review a drafted note → correct it → file it.

**The proof this product must demonstrate, and no competitor can copy-paste:**
the note is *checkable*. Select any sentence and the margin shows the exact
utterance it came from, with speaker and timestamp. That single interaction is
the whole trust argument. A cloud scribe can claim privacy; Nota can prove
provenance.

**Completeness is the second proof.** Sections the template requires but the
consultation never covered are named, not hidden — because the commonest
documentation failure is omission, not inaccuracy.

**Evidence available:** synthetic fixture transcripts only
(`fixtures/sample-transcript.txt`). No real encounters, no testimonials, no
benchmarks. The interface must never display invented clinical claims.

## 5. Surfaces

### 5.1 Menu bar (status + quick actions)

A template-rendered status item. Reflects state at a glance and is the only
always-present affordance.

- Idle → outline glyph. Recording → filled glyph plus a red dot; the red dot is
  the only place red appears in the menu bar.
- Menu: **Start recording** (⌥⌘R) · **Pause** (while recording) · **Stop and
  draft** · separator · recent encounters (last five, by pseudonym and time) ·
  **Open Nota** (⌘⇧N) · **Settings…** (⌘,) · **Quit**.
- The status item must remain legible with Reduce Transparency on.

### 5.2 Recording strip (the patient-visible indicator)

This is the most consequential surface in the product: it carries the consent
relationship. A patient who cannot see that recording is happening has not
consented to it.

- `NSPanel`, `.nonactivatingPanel`, borderless, `isFloatingPanel`, joins all
  Spaces, `fullScreenAuxiliary`, `hidesOnDeactivate = false`. It never steals
  focus from the record system.
- Positioned top-right of the active screen, inside `visibleFrame`, and moved
  to whichever screen holds the pointer at start. Never under the notch.
- Contents, ordered by reading priority: **a plain-language label** ("Recording
  consultation") in SF Pro at ≥ 13 pt, weighted to be readable across a desk; a
  live trace on a graticule; elapsed time in SF Mono tabular; **Pause** and
  **Stop**.
- Deliberately not glassy-only: with Reduce Transparency the panel resolves to
  an opaque surface with a solid border. With Reduce Motion the trace becomes a
  static level meter. Neither state loses the plain-language label.
- `sharingType = .none` is **not** used — the indicator must appear in screen
  recordings and screenshots. Hiding a consent indicator from capture would
  defeat its purpose.

### 5.3 Review window (the signature surface)

`NavigationSplitView` — encounters · document — with `.inspector` for the
margin. One window, one toolbar, three regions.

- **Encounter spines (left).** Ruled rows: pseudonym, time, discipline, state.
  State is a word first and a colour second. Columns never move; only the state
  styling changes.
- **The document (centre).** The letterhead block; then section modules in
  template order; then the signature block carrying **File note** and the
  completeness summary; then the unfiled statements, if any, above the
  signature — because they are what the clinician must resolve before signing.
- **The margin (right).** Source utterances for the whole note; the one
  matching the selected sentence is brought forward. Each mark carries its
  source index and a speaker glyph.
- Selecting a sentence selects its margin mark and vice versa. A sentence whose
  evidence is ambiguous is marked as such rather than silently attributed.

### 5.4 First run

Permissions, in this order, each with its reason stated before the system
prompt: **Microphone** (to hear the consultation) → **Accessibility** (only if
paste is enabled later; not requested in M1). Then: pick a discipline, which
sets the default template; then a 60-second demonstration on the bundled
synthetic transcript, so the clinician sees a real draft before ever recording
a patient. Then the recording-consent script, in the clinician's own words,
with a way to print it.

### 5.5 Settings

`NSWindowController` + `.fullSizeContentView`, `NavigationSplitView` sidebar,
grouped `Form` panes. Tabs: **General**, **Templates**, **Recording**,
**Privacy**, **About**.

- *Templates* is the pane that matters: per-discipline template selection, and
  a read-only view of section order and required flags. Template *editing*
  lives in the TOML files, not in a UI, until a paying practice asks.
- *Privacy* states, in plain language, that nothing leaves the Mac, and shows
  the local database path with a Reveal in Finder button.

## 6. The signature interaction

**Trace a sentence to its source.**

1. The clinician reads the note. Each sentence carries a small superscript
   reference in the margin gutter.
2. Selecting a sentence (click, or ↑/↓ while focused) highlights its margin
   mark and scrolls the margin to the matching utterance.
3. The margin shows: speaker role, timestamp, and the verbatim words. The
   matched phrase is emphasised within the utterance — not the whole line.
4. Selecting a margin mark does the same in reverse.

This must work with the keyboard alone, must be announced by VoiceOver as
"evidence for sentence n", and must never depend on colour: the selected pair
is marked by a rule and a bold weight as well.

## 7. Keyboard map

A clinician must be able to record, review and file without a mouse.

| Shortcut | Scope | Action |
|---|---|---|
| `⌥⌘R` | Global (Carbon hotkey) | Start / stop recording |
| `⌥⌘P` | Global | Pause / resume (recording only) |
| `⌘⇧N` | Global | Open Nota (review window) |
| `Esc` | Global, while recording | Stop immediately |
| `⌘,` | App | Settings |
| `⌘↩` | Review window | File note (approve) — the only path to `Approved` |
| `⌘C` / `⌘⇧C` | Review window | Copy note as rich text / plain text |
| `↑` `↓` | Document | Move selection between sentences |
| `⌥↑` `⌥↓` | Document | Jump to previous / next section |
| `⌘F` | Review window | Find in note and transcript |
| `⌘Z` `⇧⌘Z` | Document | Undo / redo an edit |
| `⌥1`–`⌥5` | Document | Focus section 1–5 |

`⌘↩` is the only control that moves a note out of `Draft`. This mirrors the
engine contract: a machine never approves a note.

## 8. States and ranges

| Element | States |
|---|---|
| Recording | idle · requesting permission · recording · paused · finalising · failed |
| Note | drafting · draft · edited · approved · no template match |
| Section | filled · empty-optional · empty-required (missing) · edited-by-human |
| Sentence | normal · selected · has-evidence · evidence-ambiguous · low-confidence |
| Encounter row | draft · edited · approved · recording · failed |
| Engine | real · mock (must be labelled in the letterhead provenance line) |
| Empty | no encounters yet · no notes for encounter · template has no cues |
| Error | audio device unavailable · storage unwritable · template missing · engine failed |

**Realistic ranges.** A consultation is 5–30 minutes. A transcript is
800–6,000 words and 40–400 segments. A note is 4–6 sections and 150–600 words.
The encounter list is 0 in week one, and 20–60 per day at the top end — the
list must stay scannable at 60 rows without pagination.

**Loading.** Transcription runs behind a determinate progress affordance in the
document region, never a blocking modal, and the window stays usable.

## 9. Layout and motion

- **Topology.** One window, three regions. The margin collapses first; the
  spines collapse second; the document never narrows below its measure. Below
  1,000 pt the margin becomes a sheet over the document rather than a squeezed
  column.
- **Density.** Note body at 68ch measure, 1.5 line height. Section rhythm:
  more space above a section header than below it. No whitespace inflation.
- **Motion.** 150–250 ms, state only. The Assemble action is the single
  orchestrated moment: transcript segments settle into ruled sections. Under
  Reduce Motion it becomes an instant state change. The recording trace moves
  because it is measuring something, never as decoration.
- **No** page-load choreography, no celebratory confetti, no spring overshoot
  on controls.

## 10. Scope and boundaries

**In scope for M1:** menu bar, recording strip, review window with margin
evidence, first-run permissions and demonstration, settings shell with the
Privacy pane.

**Explicitly out of scope for M1:** real ASR engine, model-backed generation,
EHR integration or AX paste, template editing UI, multi-user/practice features,
encryption-at-rest UI (it is an engine concern and a hard blocker for real
patient data), any marketing surface.

**Anti-goals** — a polished result that did any of these would be wrong:

- A chat interface. This is a document, not a conversation.
- A dashboard of metrics. There are no metrics worth showing a clinician.
- Glass, gradients or glow as decoration. Materials must mean something.
- Gamification, streaks, or celebratory animation. This is a legal record.
- A coloured "AI confidence" badge with no affordance behind it. Confidence
  must be checkable or absent.
- Hiding the mock-ASR state. If the note is synthetic, the interface says so.

**Must remain untouched:** the engine's contracts — traceability, no silent
drops, machine-never-approves, no patient identifiers, no network.

## 11. Constraints and open decisions

| Constraint | Consequence |
|---|---|
| Rust core exposes a C ABI with JSON envelopes | The shell parses notes as JSON and renders; it does not re-implement generation. |
| macOS 15+ target, macOS 26 for Liquid Glass | Use `#available` for `.glassEffect()` and `scrollEdgeEffectStyle`; the app must be complete and correct without them. |
| No image generation in this harness | Code-led build; no comps. |
| No network | Update mechanism and licensing must be resolved without a naive phone-home (see ADR 0002). |
| Encryption at rest not implemented | The app must refuse, in the UI, to be used with real patient data until it is. |

**Open decisions for the founder:**

1. Distribution: Mac App Store or direct? It changes the update path, the
   licensing model, and whether an Accessibility entitlement is even available.
2. The consent script wording, which must be reviewed for each jurisdiction
   before the first real recording.
3. Whether the recording strip carries the practice name (identity) or stays
   minimal (less to misread across a room).
