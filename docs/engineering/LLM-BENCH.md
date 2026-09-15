# Note engine

Production model: **Qwen3-4B Instruct 2507 Q3_K_S** (1.89 GB), written by `scribe-llm`.

Downloaded once by Settings into
`~/Library/Application Support/Klinote/Models/quire.gguf`.
The app calls it Quire. Do not surface the upstream model name in UI.
The Swift shell never talks to the network except for that download. `scribe-llm`
reads the GGUF and writes a SOAP JSON with evidence indices.

## Regression

```bash
cargo build --release -p scribe-llm
python3 scripts/note-bench.py --only quire
```

Want: `4/4` required sections, evidence `1.00`, parking leak `no`.
Gold recall is literal (`four days` vs `4 days`) — read the note, not just the score.

Not in CI. Needs the GGUF and Metal.

---

## The on-device model, measured

`NoteDrafter.swift` can write the note with Apple's on-device model through the
Foundation Models framework — no download, no second process, nothing to install.

**It is the fallback, not the destination, and that is decided.** Quire is the
note engine, settled 2026-09-15: it is what polishes a draft, and the app does not
try to do without it. The system model is what writes the note on a Mac where
Quire is not installed yet, or where a clinician declined the 1.9 GB — and it is
a much better fallback than it was. Nothing here is a plan to remove Quire, and an
earlier version of this file framed it that way; that framing is withdrawn.

Note that it is a real drafting path, not a stub. `AppModel.preferLocalDraft`
tries Quire first and falls through to `NoteDrafter`, and `NoteDrafter` runs its
own extraction *and* its own brevity pass on the system model. So the on-device
path polishes as well as drafts — the open question is only how its polish
compares with Quire's, which is the one thing this bench cannot answer without
the 1.89 GB model on disk.

This is measured, not guessed. Run it yourself:

```bash
python3 scripts/note-bench.py
python3 scripts/note-bench.py --transcript fixtures/long-consult.txt
```

That compiles `apps/Klinote/Bench/note-bench.swift` — `Sources/Domain` and
`NoteDrafter.swift`, linked against the real engine and scoring against
`fixtures/note-bench/gold-facts.json`.

Measured on 2026-09-15, Apple M4, macOS 26.6.2, Xcode 26.6 (macOS 26.5 SDK):

| Prompt shape | required | evidence | gold | leak | s |
|---|---|---|---|---|---|
| One request, all four fields | 1/4 | 1.00 | 0.273 | no | 1.7 |
| One request per field | 4/4 | 1.00 | 0.636 | no | 6.5 |
| Per field + template `guidance`/`cues` | 3/4 | 1.00 | 0.636 | no | 6.5 |
| **+ guided generation, fixed seed, chunking** | **4/4** | **1.00** | **0.909** | **no** | **12** |
| The same, on a 108-utterance consult | **4/4** | **1.00** | **0.909** | **no** | **57** |

The last two rows are the shipped shape, and they are **identical** — a long
consultation produces the same note quality as a short one. Three consecutive
runs of either produce the same numbers.

### What each change was worth, and one that was a lie

- **Asking for four fields at once does not work.** The model produced one good
  *subjective* line and stopped. A 3B model satisfies the first instruction and
  stops; it does not work through a list. One field per request fixed the
  structure.
- **The score is not the note.** The middle rows are why this file says to read
  the output. Rows 2 and 3 both look complete and both file the examination under
  Assessment, with the impression dropped.
- **Guided generation** (`@Generable` / `@Guide`) constrains decoding to the
  shape, so a truncated or chatty reply cannot arrive as a malformed draft.
- **A fixed seed, not `greedy`.** Two runs of the same code produced two
  different notes; one repeated the examination in both Objective and Assessment,
  the other dumped everything into Subjective and leaked the unclinical closing
  line into it. A note that changes between runs is not a record, so the sampling
  had to be pinned — but `greedy` was *worse*: it made the model answer "no
  statements" for Assessment on every run, reproducibly wrong.
- **Routing conflicts are resolved by the field's own `cues`** — the same
  clinician-editable vocabulary the rule-based generator uses. De-duplicating was
  not enough: a statement offered under a single wrong field has no rival, so
  first-come-first-served keeps the mistake. Statements have to be able to *move*.
- **The brevity pass must not lose statements.** It kept all four fields and
  quietly returned fewer statements inside them; the note looked complete and said
  less.

### A bug in this bench, which invalidated an earlier conclusion

The harness used to build its own `TemplateSummary` from the request and leave
`guidance` and `cues` **empty** — so the drafter was being asked to route clinical
statements into fields it had been told nothing about. It was measuring a prompt
the app never sends, and it made the on-device path look worse than it is. It now
fetches the template through `scribe_list_templates`, the same FFI call the app
makes, and **refuses to run** if the template arrives with no cues.

An earlier round concluded the on-device model failed its bar at 3/4. Part of that
was this bug. Treat any figure in this file older than the "bug" paragraph as
suspect.

### Context

`contextSize` and `tokenCount` are **macOS 26.4** APIs; on 26.0–26.3 the code
falls back to a conservative constant. On macOS 26.6 `contextSize` is **4096**,
not the 8192 of the newer model.

The transcript is split into chunks that fit, and **an over-long request is
halved and retried**. That last part matters: the per-request overhead was
estimated at 1400 tokens and the real instructions plus schema plus a template's
140 cues exceed it, so the first long-consult run came back with
`Exceeded model context window size`, one statement per field, and 103 of 108
utterances unfiled — a note that looked complete and was empty. A budget that is
an estimate must not be trusted to fail safely.

`unassigned` is still the long list to review: 9 entries on the reference
fixture. `ROADMAP.md` treats "reviewing the draft takes longer than typing" as a
kill criterion, so that number is a product concern, not just a metric.

## Quire versus the on-device model, head to head

Run this yourself:

```bash
python3 scripts/engine-compare.py                          # clean text
python3 scripts/engine-compare.py --audio <two-voice.wav>   # end to end
```

Both engines get **the same transcript and the same template**, so the only
variable is the engine. `--audio` runs the whole chain first — recognition with
`SpeechAnalyzer`, diarisation in the core — and compares them on what was heard.

Measured 2026-09-15, Apple M4, macOS 27.0, Xcode 27.0, `quire.gguf` 1.89 GB:

| | required | evidence | gold | leak | unfiled | s |
|---|---|---|---|---|---|---|
| **Clean text** — Quire 4B | 4/4 | 1.00 | 0.73 | no | 6 | 56 |
| **Clean text** — Apple on-device | 4/4 | 1.00 | 0.91 | no | 5 | 43 |
| **E2E (heard)** — Quire 4B | 4/4 | 1.00 | 0.64 | no | 10 | 53 |
| **E2E (heard)** — Apple on-device | 4/4 | 1.00 | 0.73 | no | 14 | 32 |

**Read the notes, not that table — it points the wrong way.** It says the
on-device model wins on gold recall. It does, and the reason is that it copies
the transcript verbatim, so the gold phrases survive literally, while Quire
rewrites them into clinical shorthand ("4 days" → "4 days", "q4h PRN", "q8h") and
the literal matcher then scores the *better* note lower. That is the trap this
file has warned about from the start.

What the E2E notes actually look like:

| | Quire | on-device |
|---|---|---|
| Register | "Sore throat for 4 days, pain on swallowing." | "I've had a sore throat for about 4 days now and it really hurts when I swallow" |
| Plan | rest, fluids; paracetamol 1g q4h PRN; throat swab if no improvement; return in 1 week; safety net | **"Come on in and take a seat."** and **"No, nothing like that."** filed as plan items, plus the assessment bled in |
| Utterances | kept separate | two speakers **merged into one sentence**: "…when I swallow any fever or cough." |
| Routing | safety net in Plan | safety net in Subjective; the self-care link in Subjective |

So **Quire is better, and by more than a polish margin.** It abbreviates like a
clinician; the on-device model transcribes the consultation into boxes, and in
the plan box it put a greeting and a denial. That settles the question this file
previously could not answer, and it is the measurement behind the 2026-09-15
decision to keep Quire permanent.

**The grounding check was comparing digits, and the digits happened to lie both
ways.** `support` is set by `verify_support` in the core, and on this run it did
two contradictory things:

| Sentence | Marked | Why |
|---|---|---|
| "Ibuprofen 400mg **q8h** with food." against "…**three times a day**" | `unverified` | `q8h` contributed the digit **8**, the spoken form contributed **3**. Same instruction, flagged. |
| "Paracetamol 1g **q4h** PRN…" against "…**four times a day**" | `supported` | `q4h` contributed **4** and so did "four times a day" — so it passed. But every four hours is **six** doses a day, and four times a day is every six. A real prescribing discrepancy slid through on a coincidence. |

Fixed in `crates/scribe-core/src/support.rs`: a dosing interval and a spoken
frequency are now compared as **doses per day**, and `qNh` no longer contributes
its digits as a quantity. `q8h` → 3 doses matches "three times a day" → 3;
`q4h` → 6 doses does not match "four times a day" → 4, and is flagged.

**The drug-name net works, and this file said otherwise for a while.** The
transcript for this run carries the recogniser's mangling of *cetirizine* — the
synthetic voice produced a non-word — and `suggest_names` catches it, suggesting
**cetirizine** through the vowel-skeleton distance rather than a plain edit
distance. The claim that no check fired was wrong: name checks live on the
**transcript**, and the note is what had been inspected. It is now pinned by
tests in `crates/scribe-core`, including the limit — a short mangling sharing
almost no letters ("kyrazine") falls through, because flagging it would be
guessing at a word that could be anything.

Both engines score `evidence 1.00`: every citation resolves to a real utterance.
That is the floor, not a compliment — it says the sentences are traceable, not
that they are in the right place or that anyone said them.

On the same consultation afterwards, Quire's two flagged sentences are both
**correctly** flagged: one cites only the temperature while asserting the pulse
too, and one writes `q4h` for "four times a day", which is the wrong interval.
The false positive is gone and a genuine one appeared — the check went from
coincidence to meaning.

**What it still cannot see.** `verify_support` compares numbers, doses and drug
names, deliberately: prose overlap is a bad test, because every useful note
paraphrases. So it is blind to a sentence made only of ordinary words. The
on-device model put **"Come on in and take a seat."** and **"No, nothing like
that."** in the Plan section of the E2E note, and both are marked `supported` —
faithfully quoted, entirely in the wrong place. That is a **routing** failure, and
grounding is the wrong instrument for it; `NoteRouting` and the clinician's review
are. Do not read `0 flagged` as `nothing wrong`.

Quire also repeated a finding on an earlier run — "Chest clear… no palpable
cervical lymph nodes" followed by "Cervical lymph nodes not palpable" — which
nothing flags, because no figure or dose differs.

Both engines score `evidence 1.00`: every citation resolves to a real utterance.
That is the floor, not a compliment — it says the sentences are traceable, not
that they are in the right place or that anyone said them.

### What this number is, and is not

The on-device path clears the bar the app already holds Quire to — `4/4`
required, evidence `1.00`, no parking leak — on both fixtures, deterministically.
It does **not** follow that it is as good as Quire, and this file should not be
read that way. Three things it does not say:

1. **Nothing about real consultations.** Both fixtures are synthetic. The one
   question that matters — whether a clinician would sign the draft — is a
   person, not a number, and `VALIDATION-PLAN.md` is how it gets answered.
2. **Nothing about polish.** The bar is completeness, grounding and a leak. It
   says nothing about how the prose reads next to Quire's, and polish is exactly
   what Quire is kept for.
3. **Nothing about `unassigned` being acceptable.** 9 entries on the reference
   fixture is a long list to review, and `ROADMAP.md` treats "reviewing the draft
   takes longer than typing" as a kill criterion. A product concern, not a metric.

So the useful reading is: *the fallback is no longer embarrassing*. A clinician
who has not downloaded Quire yet gets a note with the right shape and the right
citations, and the app says which engine wrote it.
