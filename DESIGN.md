# DESIGN.md — Klinote

The durable visual system for Klinote. Product truth lives in `PRODUCT.md`; the
direction and its contract live in `docs/design/UX-PLAN.md`.

Written from the built world. Tokens below are the source of truth; if code and
this file disagree, this file wins and the code is wrong.

---

## The world

**The clinical letter.** A note is a formal document addressed to the record:
letterhead, ruled field grid, structure, marginal annotation, a signature block,
a filing stamp. Klinote renders the generated note as that document and puts the
evidence in the margin, where careful readers have always put it.

Two consequences that govern every decision:

1. **Brand lives in the document, not the chrome.** The letterhead rule, the
   section tabs and the marginal marks carry identity. Toolbars, controls and
   selection use the system accent, because a clinician's accessibility
   preferences outrank our brand.
2. **Nothing is decoration.** Every rule separates something; every mark refers
   to something; every colour means something and is restated in words.

## Colour

**Strategy: Restrained.** Neutrals carry the surface; one ink accent carries
identity; two reserved semantic colours are used for nothing else.

Ground, text and selection resolve from macOS semantic colours so that light
mode, dark mode, increased contrast and the user's accent preference all work
without a second palette.

| Token | Light | Dark | Use |
|---|---|---|---|
| `ground.desk` | `windowBackgroundColor` | — | Window chrome, sidebar, toolbar |
| `ground.document` | `textBackgroundColor` | — | The note plane |
| `ground.margin` | `underPageBackgroundColor` | — | Margin column |
| `ground.recessed` | `controlBackgroundColor` | — | Inputs, non-selected rows |
| `rule.hairline` | `separatorColor` | — | Module borders, field rules, graticule |
| `text.primary` | `labelColor` | — | Note body, headings |
| `text.secondary` | `secondaryLabelColor` | — | Field labels, metadata |
| `text.tertiary` | `tertiaryLabelColor` | — | Placeholders, disabled |
| `accent.control` | `controlAccentColor` | — | Selection, focus rings, standard controls |
| **`ink`** | `#16324F` | `#9CC3E5` | Letterhead rule, section tabs, document headings |
| `ink.rule` | `#16324F` @ 22% | `#9CC3E5` @ 28% | The 2 pt letterhead rule |
| **`record`** | `#C0392B` | `#FF6B5E` | The act of recording — lamp, trace, strip border. Nothing else, ever |
| **`caution`** | `#B26A00` | `#FFB340` | A missing required section. Nothing else, ever |
| `verified` | `#1E7A4B` | `#5FD08A` | Evidence present. Only as a margin mark, never as text colour alone |

**Contrast.** All text meets WCAG AA against its own ground in both
appearances. `ink` on `ground.document` is ≥ 9:1. `record` and `caution` are
never used for body text — only for marks, rules and filled chips, each paired
with a word.

**Colour is never the only signal.** Missing sections carry the word "missing"
and a dashed rule. Recording carries the words "Recording consultation".
Selected pairs carry a rule and a bold weight.

## Type

Three system faces, no shipping fonts, each with one job.

**Every size in the product is a named role.** Nothing reaches a font by
number. The roles below are the whole set; a new one is a change to this file
first, not a number typed at a call site.

| Role | Token | Face | Size / weight | Notes |
|---|---|---|---|---|
| Note body | `document()` | **New York** (`design: .serif`) | 14 pt / regular | Line height 1.5, measure 68ch. This is the letter |
| Document title | `documentTitle()` | New York | 19 pt / semibold | The letterhead heading |
| Document aside | `documentMinor()` | New York | 13 pt / regular | Unfiled statements, a suggested name, a transcript being pasted. One step under the body so it reads as material under discussion, not as the record |
| Tagline | `tagline()` | New York | 16 pt / medium | The line under the wordmark |
| Section tab | `tab()` | SF Pro | 11 pt / semibold | Uppercase, `+0.6` tracking, `text.secondary` |
| Field label | `label()` | SF Pro | 11 pt / medium | `text.secondary` |
| Micro label | `micro()` | SF Pro | 9 pt / semibold | Chip text. The smallest step in the product |
| Body / control | `ui()` | SF Pro | 13 pt / regular | All interface text |
| Emphasis | `emphasis()` | SF Pro | 13 pt / semibold | Button labels, a selected sentence |
| Panel heading | `panelHeading()` | SF Pro | 15 pt / semibold | A heading inside a sheet or an empty state |
| Caption | `caption()` | SF Pro | 12 pt / regular | Explanatory text under a control, a promise, or an error |
| Margin utterance | `utterance()` | SF Pro | 12.5 pt / regular | `text.secondary`; matched phrase semibold, `text.primary` |
| Data, time, IDs | `data()` | **SF Mono** | 11 pt / regular | Tabular figures, always |
| Micro data | `microData()` | SF Mono | 10 pt / regular | Counts and row metadata in the margins |
| Micro number | `microNumber()` | SF Mono | 9 pt / regular | The margin number tying a sentence to its evidence |
| Clock | `clock()` | SF Mono | 12 pt / regular | The recording clock, menu-bar titles |

**Scale ratio 1.2**, fixed. No fluid or clamp-sized type: a Mac is viewed at
consistent DPI and a heading that shrinks in a narrower pane looks broken.

**Why New York.** The document needs to read as a document, and New York is
Apple's reading serif — present on every Mac, hinted for screen, and it makes
the note plane feel like paper without any paper texture or cream ground. It is
also the honest choice for a native app: we are not shipping a display face.

Banned in this product: any display serif used for UI labels; monospace for
prose; letter-spaced small caps larger than 12 pt.

## Space, rules and shape

- **Spacing scale:** 4 · 8 · 12 · 16 · 24 · 32 · 48. Sections are separated by
  32; more space above a section tab than below it (24 above, 12 below).
- **Inline scale:** 2 · 6. Chips, a field label against its value, and the
  inside of a row need finer steps than the layout scale allows. These two
  exist so those gaps are a decision rather than a typed number. No other
  value below 4 may appear in the product.
- **Radii:** document plane 10 · module 8 · inline chip 4 · lamp 2. The letter
  is squared; only the plane is softened.
- **Modal chrome:** one sheet family, so one width (620) and one inset (24).
  Three sibling sheets had drifted to 520/620 and 24/32, which reads as three
  products rather than one.
- **Symbol sizes:** 11 · 13. Two steps, no others.
- **Rules:** module border 1 px `rule.hairline`; field rules 1 px at 60%
  opacity; the letterhead rule is the only 2 pt rule in the product, in `ink`.
- **Elevation:** exactly one shadow in the product — a 1 px `rule.hairline`
  border plus a very soft 8 pt shadow on the document plane. Modules never
  float.
- **Materials:** the letter, sidebar and evidence column are **opaque paper
  and desk**. Liquid Glass is reserved for the floating recording strip (a
  panel over the desktop). Clear split-view columns are unreadable. Reduce
  Transparency makes the strip opaque desk. `#available(macOS 26)` only.

## Components

Every interactive component ships all of these states or it does not ship:

| Component | States |
|---|---|
| Section module | filled · empty-optional · **missing-required** (dashed `caution` rule + the word "missing") · human-edited (a 2 pt left rule in `ink` + "edited" tab suffix) |
| Sentence | normal · hover · selected (rule + 1.06 bold, not colour alone) · evidence-ambiguous (dotted mark + "unclear source") · low-confidence (mark shows a `?`) |
| Margin mark | unsourced · sourced (index number) · active · ambiguous |
| Study row (encounter) | draft · edited · approved · recording · failed |
| Primary action | default · hover · pressed · focused · disabled · in-flight ("Filing…") |
| Recording lamp | off · recording (pulsing, 2 s) · paused (steady, hollow) |
| Trace | live · paused (held, dimmed) · reduced-motion (static level meter, 8 bars) |
| Progress | determinate bar in the document region; never a modal spinner |

**The letterhead block** (top of the document plane), in order: practice name
(user-set, falls back to the discipline) · encounter reference in SF Mono ·
date and duration in SF Mono · the **provenance line**, always visible: the
generator engine, and if the engine is the mock, the words *"synthetic sample
text — not a real transcription"* in `caution`. Then the 2 pt `ink` rule.

**The signature block** (foot of the document): a rule, then the clinician's
name and registration line on the left, the completeness summary in the middle
("4 of 4 required sections documented", or the missing ones named in `caution`),
and **File note** (⌘↩) on the right. Nothing else may sit in this block.

**Unfiled statements** sit above the signature block, never below it and never
hidden behind a disclosure: they are what the clinician must resolve before
signing.

## Motion

| Motion | Duration | Easing | Purpose |
|---|---|---|---|
| State change (hover, select, toggle) | 160 ms | `.easeOut` | Feedback |
| Layout (margin collapse, pane resize) | 220 ms | `.easeInOut` | Continuity |
| **Assemble** (transcript → ruled letter) | 420 ms, once | `.easeOut` | The single orchestrated moment: segments settle into sections |
| Recording lamp pulse | 2 000 ms | `.easeInOut`, repeat | Liveness |
| Trace | continuous | — | Measurement, not decoration |

- No entrance choreography, no overshoot, no celebration. This is a legal
  record.
- **Reduce Motion:** Assemble becomes an instant swap; the lamp becomes a steady
  filled square; the trace becomes a static level meter. No state loses
  information.
- **Reduce Transparency:** every panel resolves to an opaque ground with a
  1 px border.

## Voice

Plain, clinical, unhurried, and never cheerful about risk.

| Instead of | Write |
|---|---|
| "AI is thinking…" | "Transcribing…" |
| "Oops! Something went wrong." | "The microphone stopped responding. Recording was saved up to 04:12." |
| "3 issues found!" | "2 required sections are missing: Objective, Plan." |
| "Your note is ready! 🎉" | "Draft ready for review." |
| "This may not be accurate" | "Synthetic sample text — not a real transcription." |

Rules: no exclamation marks; no emoji anywhere in the product; name the thing
that happened; state what to do next; never claim accuracy we have not measured;
never say "AI" when the honest word is "draft".

## Accessibility

- Contrast ≥ 4.5:1 for all text, ≥ 3:1 for rules that carry meaning.
- Full VoiceOver labels; the evidence relationship announced as "evidence for
  sentence 4".
- Focus order follows the document, then the margin. The margin is reachable by
  keyboard from the sentence it belongs to.
- Never colour-alone. Never icon-alone. Never truncate clinical content — wrap
  it.
- At the largest system text sizes the document measure grows rather than the
  text shrinking; the margin collapses before the document narrows.
- Target sizes ≥ 24 × 24 pt for pointer targets in the margin.
