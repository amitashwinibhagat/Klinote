# Screens from the jobs

Jobs: `docs/product/JTBD.md`. Sequence: `docs/design/UX-FLOW.md`.
This file is the screen list. If a surface does not serve a named job, it
does not ship.

**Rule:** one job, one surface. The letter is not also the caseload. The
strip is not also the note. Copy is not also file-in-the-EHR.

**Still a hypothesis.** Zero interviews. A therapist who will not capture
at all kills screens 2–3, not the letter.

---

## The jobs, and the screen each one owns

| Job (when → so I can) | Screen | Primary action |
|---|---|---|
| First open: see I can check a sentence before a 2 GB wall | **S0 · Sample** | Click a sentence |
| Client just left; get this hour in, in ten minutes | **S1 · Desk** | Dictate / type / record |
| Recording *during* the session; client must see it | **S2 · Session lamp** | Stop |
| Dictating *after*, empty room, mic on me | **S3 · Dictate lamp** | Stop |
| Defend every sentence; kill an invented line; swap voices | **S4 · Letter** | Copy note |
| Get it into the record I already use | **S5 · Copied** | Dismiss / next |
| Find Tuesday’s note, not live in a register | **S6 · Earlier** | Open one letter |

**Not a screen this round**

| Job | Why not |
|---|---|
| Process note that cannot paste into the record | Adjacent, unbuilt, unasked. A second output on S4 later — not a home. |
| Settings, templates, retention | Maintenance. Not the struggling moment. |

The current app is **S4 + S6 fused into one window, with S2 as the only
capture, and no S0/S1/S3/S5.** That fusion is why it feels like an EHR.

---

## S0 — Sample

**Job.** First-run wall: I need to see a letter before a download.

**When.** First launch, or “show me again.”

**On the page.** One progress note. Already filled. One line: *Click a
sentence.* The words appear beside it. Copy is visible. A caption: *Sample
text — not a real session. Nothing leaves this Mac.*

**Not on the page.** Download progress. A legal essay. A list of sessions.
A record button as the first thing.

**States.** Clicked / not yet. Copy on sample is allowed (it teaches the
path). Record and the “I will tell the client” tick live behind Record, not
here.

**Kills.** Setup sheet as first paint.

---

## S1 — Desk (home)

**Job.** Core job, the first half: the client just left; I need this hour
in.

**When.** 14:52. Eight minutes. Not browsing.

**On the page.** One question: *How is this session getting in?* Three
peers, same size:

1. **Dictate the note** — you talk, empty room.
2. **Type or paste** — the words, on this page, no role prefixes.
3. **Record the session** — client in the room, lamp they can see.

If Tuesday 14:00 was never copied: one row under the three, *Copy it.*
That is the only inbox.

**Not on the page.** A search box. A spine of twenty encounters. A plus
that only records.

**States.** Empty day / one uncopied / dictating / typing. Opening S1
never waits on a download.

**Kills.** Encounter sidebar as the default home.

---

## S2 — Session lamp

**Job.** During the session: recording visible and honest.

**When.** Client is in the chair. Hands are busy. They are not looking at
a letter.

**On the page.** Floating strip only. Lamp, clock, *Recording this
session. Audio stays on this Mac.* Pause. Hold (this part is not in the
note). Stop.

**Not on the page.** The letter. Evidence. Copy. A window behind the
client’s eyeline that looks like an EHR.

**States.** Recording / paused / holding / writing the note.

**Kills.** Nothing — this surface is already the right object. It must not
be the *default* capture.

---

## S3 — Dictate lamp

**Job.** Same core job as S1, capture = their voice after the client left.

**When.** Empty room. They talk for two minutes: what was said, risk, plan.

**On the page.** Same strip *object*, different promise: *Dictating the
note. Audio stays on this Mac.* No “tell the client” — there is no client
in the room. Stop → S4.

**Not.** A second product. Not a paste sheet with `CLINICIAN:`.

**Kills.** Treating dictate as a consolation for a failed download.

---

## S4 — Letter (the product)

**Job.** Core, second half + invented line + swap voices.

**When.** There is a draft. They have minutes, not an afternoon.

**On the page.**

- Progress note: Presenting · **Risk** · What we did · Plan.
- Risk empty ⇒ Copy disabled until they write it or write “not discussed.”
  The machine never fills risk.
- A quote that is not in the words is not on the page.
- **Words for the selected sentence, always on.** That column is the job
  “I did not say that.” Closing it closes the product.
- One tap: swap therapist / client.
- One primary: **Copy note.**
- Secondary: write this line (authored, survives redraft).

**Not on the page.** SOAP. MSE-as-therapy. A caseload. Print, referral,
client summary as peers of Copy. A signature that thinks it is the EHR.

**States.** Drafting · ready · risk missing · unfiled lines · swapping ·
sample (read-only copy still ok).

**Kills.** Three equal columns on launch. Copy as the third toolbar icon.

---

## S5 — Copied

**Job.** Extra clicks into the EHR: paste into the record I already use.

**When.** They just copied.

**On the page.** The letter stays. One line on it: *On the clipboard. Paste
it into the record you already use. Nothing left this Mac.* Then they
⌘-tab out. We do not follow them.

**Not.** A filing ceremony. A “mark as signed.” A success animation.

**States.** Copied / copy blocked (risk, or the wrong session — then the
existing confirm, still about a *session*).

---

## S6 — Earlier

**Job.** Not the core job. “I need Tuesday’s note.” Rare, in the ten-minute
window.

**When.** They asked. Not by default.

**On the page.** A list of *today, then earlier*. Open one → S4. No search
as the first control. No plus that records.

**How they get here.** One control on S1: *Earlier.* Not a permanent third
of the window.

**Kills.** The encounter register as home.

---

## Sequence (Tuesday)

```
S1 Desk
  ├─ Dictate  → S3 lamp → S4 letter → S5 copied → S1
  ├─ Type     → S4 letter (words on the page) → S5 → S1
  └─ Record   → S2 lamp  → S4 letter → S5 copied → S1

First launch: S0 sample (click a sentence) → S1
“Tuesday 14:00”: S1 inbox row → S4 → S5
“Find last week”: S1 → S6 → S4
```

The current app is: launch into S6+S4 glued together, S2 only, no S1, no S3,
S0 blocked by setup.

---

## What a builder must not invent

- A fourth capture path.
- Process vs progress as a toggle on S1.
- DAP/BIRP picker before a therapist names the form — S4 uses Presenting /
  Risk / What we did / Plan until then.
- An EHR button.
- Closing the words column on S4.
- Making Record the default control on S1.

---

## Confirm before building

This plan is only worth code if:

1. **S1 is home**, not the encounter list.
2. **Dictate and type are peers of record**, not a paste sheet.
3. **S4 opens only once there is a draft.**

If those three are wrong, do not implement. Rewrite this file.
