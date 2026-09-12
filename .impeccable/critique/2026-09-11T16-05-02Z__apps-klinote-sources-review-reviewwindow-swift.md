---
target: the review window
total_score: 31
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/Users/amitashwini/Projects/Local Clinical Scribe/apps/Klinote/Sources/Review/ReviewWindow.swift"
target_fingerprint: "sha256:563e0b4e0b42a1e3b9058bfb84a8ef20cb1d79a3166ff4b2e13febbb2a6c8490"
target_path: /Users/amitashwini/Projects/Local Clinical Scribe/apps/Klinote/Sources/Review/ReviewWindow.swift
timestamp: 2026-09-11T16-05-02Z
slug: apps-klinote-sources-review-reviewwindow-swift
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Status row, provenance and copy banner are strong; the evidence header that says *which* sentence is selected is truncated to "Words that produced sen…", removing the one piece of state the margin exists to show |
| 2 | Match System / Real World | 4 | Clinician-native throughout: Subjective/Objective/Assessment/Plan, monospace for temperatures and times, "Tell the patient". No translation layer |
| 3 | User Control and Freedom | 3 | Double-click to correct, Esc to cancel, hold, speaker swap, delete with confirmation. No undo for a correction — re-editing is the only recovery |
| 4 | Consistency and Standards | 3 | Tokens now enforced. But three differently-meaning "check …" affordances coexist: *check source*, *check wording*, *Check these names* |
| 5 | Error Prevention | 4 | Wrong-consult copy guard, delete confirmation, drug names suggested never applied, silent-shorthand never rewritten |
| 6 | Recognition Rather Than Recall | 3 | Evidence margin is the recognition aid by design, but its truncated header forces the clinician to remember which sentence they selected |
| 7 | Flexibility and Efficiency | 3 | Global hotkeys, Consult and Edit menus, print, search. No multi-select or bulk action on encounters, which the day's 40 consults will want |
| 8 | Aesthetic and Minimalist Design | 3 | The letter itself is excellent. Composition is asymmetric: 50 pt of inset on the left of the document, 195 pt of dead desk on the right |
| 9 | Error Recovery | 3 | Errors are concrete and actionable ("Allow the microphone in System Settings"); a denied store key explains its own fix |
| 10 | Help and Documentation | 2 | Shortcuts are documented in Settings; .help tooltips exist. Nothing explains the evidence-margin model, which is the product's central idea |
| **Total** | | **31/40** | **Good** |

## Design Specificity Verdict

**LLM assessment.** Genuinely authored. The letter metaphor is not decoration: the 2 pt letterhead rule is the only 2 pt rule in the product, recording red is reserved for the act of recording and never appears in the mark, and monospace is used exclusively for figures a clinician might read back to someone. The numbered margin that ties a sentence to the words that produced it is a product-specific idea, not a pattern borrowed from a note-taking app. **Could an unrelated product use this unchanged? No.** A CRM could not use a letterhead rule plus a numbered evidence margin plus a hold control.

The specificity is strongest exactly where the product makes a claim: in the proof that a sentence came from something the patient actually said.

**Deterministic scan.** `detect.mjs` returned `[]`, exit 0. **This is a null result, not a pass.** The detector reads HTML and CSS; this target is SwiftUI. There is no deterministic signal for this surface, and I am not reporting a clean scan as evidence of quality. The equivalent pass — audit.native — has not run.

**Visual overlays.** None. Browser injection is not applicable to a native app, and `live` is web-only.

## Overall Impression

At 1280 pt — the app's *own default window size* — the evidence column is squeezed to roughly 160 pt against a declared minimum of 260, and its own labels are clipped. The product's differentiator is the audit trail, and the audit trail is the part that does not fit. Everything around it is in good shape: the letter is beautiful, the copy is clinician-native, and error prevention is unusually strong for a product this young.

The single biggest opportunity: stop treating the evidence margin as an optional third column and size the window for the product's actual shape.

## What's Working

1. **The letter.** Serif body at a 68-character measure, a 2 pt ink rule, monospace metadata. It reads as a document rather than as a form, which is what makes "paste this into the record" feel plausible.
2. **Evidence in the margin, not in a panel.** Putting the source beside the claim — rather than behind a disclosure — is the correct structural decision for a product whose promise is verifiability.
3. **Error prevention.** Holding, the copy guard, suggested-not-applied drug names, and the refusal to silently rewrite an ambiguous abbreviation are all cases where the product chose the slower path deliberately.

## Priority Issues

### [P1] The evidence column does not fit at the window's own default size
- **What**: Sidebar 260 + document 624 + inspector 320 needs 1204 pt. The default window is 1280 and the declared minimum is 1040. At 1280 the inspector renders at ~160 pt, below its 260 minimum, and clips: the header truncates to "Words that produced sen…", the picker to "Who…", and utterance text runs to the window edge.
- **Why it matters**: The margin is how a clinician answers "why is this in my note?" — the product's central claim. At the default size it is unreadable, and the declared minimum of 1040 makes it worse rather than better. This is the one defect that undermines the pitch rather than the polish.
- **Fix**: Raise `minSize` to ~1260 and let the document pane flex rather than hold a fixed 560. Shorten the margin labels to fit 260 ("Sentence 3", "Evidence | Full"). Consider defaulting the inspector closed below ~1200.
- **Suggested command**: `$impeccable adapt`

### [P1] Two margin labels truncate because they cannot wrap or shorten
- **What**: `Text("Words that produced sentence \(n)")` and the two-option segmented picker have no wrapping, no line limit and no short form, inside a 260–320 pt column.
- **Why it matters**: The header restates which sentence is selected — the working-memory aid that lets a clinician read the margin without holding the letter in their head. Truncated, the aid is gone and the sentence must be recalled. It also reads as broken, at exactly the moment the product is asking to be trusted.
- **Fix**: `fixedSize(horizontal: false, vertical: true)` on the header, or shorten to "Sentence 3"; shorten the picker to "Evidence | Full".
- **Suggested command**: `$impeccable clarify`

### [P1] Accessibility coverage is thin on the most-repeated elements
- **What**: 11 `accessibilityLabel` calls across six files. Sentence rows and utterance rows are labelled, but section headings, the letterhead fields, the status line and the sidebar's search field are not. The evidence margin conveys its crucial fact — which row is the source — through a colour change and a "source" chip.
- **Why it matters**: Persona Sam cannot complete the primary flow aloud. The margin's "source" marker is a visual chip with no announcement, so the relationship between sentence and evidence is invisible to VoiceOver.
- **Fix**: Label the section headings and the primary-evidence row; announce selection changes. Run `$impeccable audit` for contrast and traversal.
- **Suggested command**: `$impeccable audit`

### [P2] The document sits off-centre in its own pane
- **What**: The document plane is left-aligned inside a frame that fills the detail pane, leaving ~50 pt of inset on the left and ~195 pt of empty desk on the right at 1280.
- **Why it matters**: 4:1 asymmetry reads as an accident. In a product whose entire argument is that it was carefully made, uneven dead space is the cheapest way to look careless.
- **Fix**: Centre the document in the pane, or deliberately widen the measure to use the space.
- **Suggested command**: `$impeccable layout`

### [P2] The letterhead stacks six elements before the first section
- **What**: Brand mark, title, metadata row, provenance line, amber "Sample text — not a real consult.", "Click a sentence to see the words that produced it.", then the rule.
- **Why it matters**: Three consecutive notices compete with the title for the first glance, and the amber caution — which is correct and important on a demo note — pulls attention away from the document itself.
- **Fix**: Fold the hint into the margin header where it belongs (it is about the margin), leaving one provenance line and the caution.
- **Suggested command**: `$impeccable distill`

## Persona Red Flags

**Sam (accessibility-dependent), primary flow = check a sentence against what was said**
- The margin's "source" chip is visual only; nothing announces that row 5 is the source of sentence 2.
- Section headings ("SUBJECTIVE") are styled text, not headings, so the letter has no navigable structure for a screen reader.
- The selected sentence is conveyed by a full-width colour block; with colour differentiation off, the selection is invisible.
- 11 labels across six files is thin for a surface with this many repeated rows.

**Alex (power user), primary flow = 40 consults a day**
- No multi-select, so clearing a day's unreviewed notes is 40 individual actions.
- The encounter row duplicates its actions in both a "…" menu and a right-click menu; neither is keyboard-reachable without a mouse.
- Corrections are per-sentence with no undo, so a mis-edit costs a re-edit rather than ⌘Z.
- Nothing is faster than the mouse in the sidebar.

**Riley (stress tester)**
- A consult with a long patient reference will push the encounter row into the "…" control.
- The evidence column is the failure surface: narrow the window and the margin breaks before anything else, so the product degrades in its signature feature first.
- Nothing prevents two consults being open as sibling documents and the wrong one being printed; the guard covers copy, not print.

## Minor Observations

- The toolbar clusters four controls at the left rather than the platform-typical trailing action group.
- "Still to do" is absent when there are no tasks, so the sidebar's capability is invisible until it has content.
- The sidebar is largely empty space below one row; it does not use its height to explain itself.
- The "Printed" path reuses the record text, which is right, but the print job carries no letterhead.

## Questions to Consider

- The evidence margin is the product's differentiator. Should it be a third column at all, or a layer that takes over the letter when a sentence is selected?
- If the window cannot be smaller than ~1260 without breaking the margin, is the three-column shape the right one for a 13-inch MacBook at 1440×900?
- What would this look like if the letter, not the sidebar, were allowed to be the widest thing on screen?
- Does a clinician ever need the encounter list and the evidence margin visible at the same time?
