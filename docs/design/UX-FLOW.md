# UX flow — the hour after the session

This is the flow we should have designed. The shipped shell is still a GP
encounter browser with the nouns swapped. That is why it feels the same.

Not code. Not tokens. The sequence a therapist lives.

---

## Who walks in

It is 14:52. The client has just gone. The 15:00 is in the waiting room.
They have eight minutes. They are not browsing a caseload. They are trying
to get *this hour* into the record without staying until 19:00, and without
a recording of that room existing on a US disk.

They have already tried Upheal or Mentalyc. Something in the draft was not
said. They quit because the audio left, not because the editor was ugly.

They may refuse to record the session at all. That is not an edge case. It
is the default in a lot of rooms. If the product’s first gesture is a red
record lamp, we have already picked the wrong job.

Pain, in order:

1. I have to write this note before the next person sits.
2. I will not send this session to a vendor.
3. I will not sign a sentence the client did not say — especially risk.
4. Recording *during* the hour may be forbidden, or it changes the work.

What they do not have: an EHR census to manage, a GP SOAP, a waiting room
of 28 six-minute slots, a need to “search consults.”

---

## What is wrong with the thing on screen today

The window is three columns: a list of encounters, a clinical letter, an
evidence margin. That is an EHR. It is the right object *after* there is a
note. It is the wrong place to *start*.

Home is a caseload. The job is one session, now.

Record is the hero. For this person, record is the ethically hardest path.

Paste is a clipboard icon and a sheet that still asks for `CLINICIAN:` /
`PATIENT:` lines. After a session they do not have a transcript. They have
ten minutes of their own voice, or a paragraph they typed.

The letter is still a filed document you inspect. The job is: check it did
not invent, then copy. Inspection is the whole product, but it is parked in
a side column.

First-run still looks like medical software that needs a 2 GB download
before it will talk to you.

Renaming “consult” to “session” does not touch any of that.

---

## The flow (four moments)

### 0. First run — prove the hire in thirty seconds

They open Klinote. They see **one progress note**, already on the page.
Not a setup wall. Not a download. Not an empty caseload.

One instruction, on the note: **Click a sentence.**

They click. The words that produced it appear beside it. That is the
product. Upheal does not do this. That is why they are here.

Then, and only then: Copy is visible. “This never left the Mac.”

Download listening only if they choose **Record**. Dictate and paste never
wait on Whisper. The teaching checkbox (“I will tell the client”) lives on
the record path, not in front of the sample.

If first-run is a settings sheet, we have already lost.

### 1. Between sessions — the actual home

Not a list. A desk with one question:

**How is this session getting in?**

Three peers, equal weight, none apologising for itself:

| Path | When | What happens |
|---|---|---|
| **Dictate** | Client just left. They talk for two minutes in an empty room. | Mic on *them*, not on the session. Strip says “Dictating the note. Audio stays on this Mac.” Stop → letter. |
| **Paste or type** | They already wrote it, or they will type the hour in one pass. | The letter itself takes the words. No `CLINICIAN:` ritual. A box on the page: “What was said, or what you need in the note.” |
| **Record the session** | They have consent, they mean it, the client can see the lamp. | Today’s strip. Hardest path. Not the default. |

Under that, if the last note was never copied: one line, one button.
“Tuesday 14:00 is still on this Mac. Copy it.” That is the only ‘inbox.’

Yesterday’s sessions exist behind a single control — “Earlier” — not as
the left third of the window. A therapist does not live in a register.

### 2. The letter — check it did not invent

Now the three-column object earns its keep, but the weights change.

**Centre: a progress note, not a GP letter.**
Presenting / Risk / What we did / Plan. (DAP/BIRP when a therapist names
the form. Until then, this shape. Not SOAP. Not MSE-as-therapy.)

**Risk is a gate.** Empty risk is not “Not documented.” It is the thing
they cannot copy past. Either they write “not discussed” or they write
what was said. The machine never fills it.

**A quoted line that is not in the words does not appear.** That is the
Mentalyc-firing, as a rule, not a caption.

**Right: the words, always, for the selected sentence.** Not a panel you
toggle. The review *is* “did I invent this.” If the margin is closed, the
product is closed.

**Left: gone, or a thin spine of today only** if they already made three
notes this afternoon. Not “Encounters.” Not a search box as the first
control.

Primary action, one, fat, on the letter: **Copy note.**
Secondary: I wrote this line. Swap voices. That is all.

### 3. Copied — get out of the way

Banner: “On the clipboard. Paste it into the record you already use.
Nothing left this Mac.”

The letter stays. They ⌘-tab to SimplePractice. We do not pretend to be
the record.

If they have three minutes left, home (moment 1) is one gesture away.

---

## What each moment is *not*

| Moment | Not |
|---|---|
| First run | A 2 GB gate, a legal essay, a SOAP sample |
| Home | An encounter list, a plus button that only records |
| Capture | A paste sheet that requires role prefixes |
| Review | SOAP, MSE, “Clinical note”, Copy as one of four toolbar icons |
| After copy | A filing ritual, a signature that thinks it is the EHR |

---

## What we keep from the current app

The letter as an object (ruled, cited, not a chat).
The strip when they actually record (client must see it).
Encryption, local-only, machine never signs.
Click-a-sentence → words. That interaction is the brand.
Authored lines survive a redraft.

Everything else — the caseload home, record-as-hero, SOAP default,
`PATIENT:` paste, setup-before-sample — is the previous product.

---

## Build order, if this brief is accepted

1. **Home is capture, not the register.** One session, three peers, last
   uncopied note. The three-column letter opens *after* there is a draft.
2. **Dictate-after** as a first-class path (mic on the therapist, empty
   room). Same engine, different promise on the strip.
3. **Paste/type onto the letter**, no role-prefix ceremony.
4. **Progress-note shape** as the letter. Risk cannot copy empty.
5. **Margin cannot hide** during review.
6. **First-run is the sample progress note + click a sentence.** Download
   and the recording acknowledgement follow the record path only.

Do not start with another pass on labels. If the home screen is still a
list of encounters, it is still the old app.
