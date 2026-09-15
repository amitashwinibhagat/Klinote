---
target: the review surface (ReviewWindow.swift + DocumentView.swift)
total_score: 30
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 4
target_identity: "file:/Users/amitashwini/Projects/Klinote/apps/Klinote/Sources/Review/ReviewWindow.swift"
target_fingerprint: "sha256:1d5f2a290544155971caf8e6ca46b04cfa902692aab32d2a9eb926fd6fc4063e"
target_path: /Users/amitashwini/Projects/Klinote/apps/Klinote/Sources/Review/ReviewWindow.swift
timestamp: 2026-09-15T15-35-48Z
slug: apps-klinote-sources-review-reviewwindow-swift
---
# Critique — apps/Klinote/Sources/Review (ReviewWindow + DocumentView)

Method: DEGRADED single-context. Three isolated sub-agents (A design, B evidence, native audit) were
each interrupted mid-run and returned no output; A and B were then run sequentially inline. Detector
inapplicable: detect.mjs returns [] on Swift (HTML/CSS parser). No screenshots or goldens exist in
repo, so all findings are source-level; rendered pixels, in-situ contrast and VoiceOver output
unconfirmed.

## Design Health Score: 30/40 (Good). No heuristic marked n/a (Operate surface).
1 Visibility 3 | 2 Real world 4 | 3 Control 3 | 4 Consistency 2 | 5 Error prevention 3
6 Recognition 3 | 7 Flexibility 3 | 8 Aesthetic 4 | 9 Error recovery 3 | 10 Help 2

## Specificity: authored, not category-default. Evidence margin, sentence numbering, consent-gated
name replacement, unfiled statements above the signature block. documentMeasureMin (Tokens:224-228)
is a priority statement expressed as arithmetic: the letter gives up width before the evidence
column does.

## Priority issues
[P1] Two safety flags share one slot, weaker one wins. DocumentView:531 `if isJargon` / :543
`else if isUnverified`. A sentence with ambiguous Latin AND an unheard figure shows only "check
wording"; the flag meaning "this number did not come from the room" is suppressed. Render both or a
third state. -> polish
[P1] `caution` means four things, against its own contract. Tokens:11-12 and :49 ("A missing
required section. Nothing else, ever."), used for missing (:163), jargon (:534), unverified (:546),
while SettingsView:224/:256 use raw `.orange`. A colour whose only job is "look here" stops meaning
anything with four owners; colour-blind clinicians cannot order severity. -> colorize, polish
[P1] Flag carrying the product's central promise is the smallest type in the app: micro() = 9pt
semibold (Tokens:117-119) vs 14pt serif body, read at arm's length in three minutes. Raise to
10-11pt, add a non-colour cue. -> typeset
[P1, needs VoiceOver confirmation] Row label may announce "Sentence 3" instead of the note.
DocumentView:579 `.accessibilityElement(children: .combine)` then :580 explicit
`.accessibilityLabel("Sentence N")`; explicit label overrides combined children, and :581 handles
`ambiguous` but never `isUnverified`. Inferred from API semantics, not observed. -> audit, harden
[P2] Settings speaks a different visual language from Review: `.foregroundStyle(.secondary)` /
`.font(.caption)` ~20x in SettingsView:59-394 vs KlinoteColor/KlinoteFont throughout Review. -> polish
[P2, verify first] No `List` anywhere; ScrollView+ForEach at MarginView:65-67 (108 utterances),
DocumentView:20-26/:358, ReviewWindow:358-362. Confirm VStack vs LazyVStack at 4 call sites. -> optimize

## Strengths
Colour resolves from NSColor semantic names (Tokens:19-29) so light/dark/increased-contrast/accent
all work with no second palette; the three hand-authored colours each carry a dark twin via one
dynamic() helper (:55-59). Reduce Motion defined once (:251-261), injected from
NSWorkspace.accessibilityDisplayShouldReduceMotion (ReviewWindow:142, RecordingStrip:166), read at
each animated site (DeskView:13/177, Components:173). Tooltips name the specific problem and why the
machine will not fix it (DocumentView:541, :553).

## Personas
Alex: no keyboard route to a sentence's evidence (onTapGesture :571-572); no "jump to next flag".
Sam: label override above; isUnverified never spoken; `?` glyph (:519) is a visual-only marker;
.accessibilityHidden(true) at DeskView:231/240/262, MarginView:222 to confirm.
Riley: NoteEditing.swift:40 sets support=nil on edit while AppModel.swift:1331 sets "supported" —
same act, two states.
Clinician at 6:40pm: scans for flags; both flags cannot show, both are 9pt, both share the colour of
"required section missing".

## Minor
9pt micro also drives sentence numbers app-wide (system question, not one label).
documentMinor() 13pt vs document() 14pt asked to carry "material under discussion vs the record".
Empty state for zero encounters in DeskView unconfirmed (skeleton loaders prove loading is handled).

## Questions
What if a flagged sentence were the only thing that moves? Does "check source" need to be a chip, or
should the sentence's own rule carry the state? The grounding check just became trustworthy enough to
catch a wrong dose interval — should the UI be allowed to look that confident about it?
