# Klinote — Landing Page Copy

Framework: **PAS** (Problem–Agitate–Solution). Chosen over AIDA/StoryBrand because
the Pelmatech design's three-card grid is *already* a problem-agitation block
(titles: Unavailable / Unethical / Waitlist), so the framework and the layout
agree instead of fighting.

## The constraint that shapes every line

`docs/product/PRODUCT-TRUTH.md` is the source of truth for what may be claimed,
and it is blunt: **"Evidence on Hand: None."** No pilot clinician, no
testimonials, no logos, no benchmarks, no outcome data. No medical, regulatory
or compliance claim has been assessed.

Therefore this page **fabricates nothing**. Where the copywriter's framework
asks for social proof, this page substitutes *checkable engineering facts* —
each one verifiable in this repository:

- The Rust engine has no HTTP client (CI-enforced by `scripts/check-network-surface.sh`).
- Speech recognition is the system's `SpeechAnalyzer` — it makes no request at all.
- Notes at rest are SQLCipher-encrypted; the key is in the Keychain.
- Nothing the generator cannot route is dropped — it goes to `unassigned`, with a regression test.

Claims that are **not** made anywhere on this page, because they are not yet
true: "accurate", "clinically validated", "saves you N minutes", "HIPAA/GDPR
compliant", "integrates with your EHR", "medical device". The word "AI" is not
used; the honest word is "draft".

---

```
LANDING PAGE COPY
Product/Service: Klinote — on-device ambient clinical documentation for macOS
Framework: PAS (Problem–Agitate–Solution)

========================================
HERO SECTION
========================================

Headline: The session stays in the room. The note still gets written.

Subheadline: Klinote turns a session — recorded or dictated — into a
structured progress-note draft entirely on your Mac. Every sentence cites the words that
produced it. Nothing is uploaded — there is nothing to upload to.

CTA Button: "Request early access"
Secondary:  "How it works"

Trust Bar: No account · No upload · Encrypted at rest · The machine drafts, you sign

========================================
PROBLEM SECTION  (three-card grid)
========================================

Section intro:
  Left:  What a cloud scribe costs you
  Right: The objection is rarely the editor. It is the disk, the invention and
         the missing receipt — three problems that a better text box does not fix.

Card 01 — "Uploaded"
  We understand that there may be times when a session cannot exist on a
  vendor's disk. Licence, ethics, or law says the room stays in the room — and
  the recording leaves before the note is written.

Card 02 — "Invented"
  A draft that puts words in the client's mouth is worse than no draft: a risk
  they did not name, a feeling they did not describe, a plan they did not
  agree to. You cannot sign that — and you should not have to rewrite it
  either.

Card 03 — "Untraceable"
  When a sentence arrives with no source, the only honest question is "why is
  this in my note?" — and "the model said so" is not an answer a record accepts.

========================================
SOLUTION SECTION  (carousel = "How it works")
========================================

Eyebrow: Klinote · How it works
Heading: Five steps, and the fourth one is the product

Intro: Most of a note is not writing — it is deciding where each sentence
belongs. Klinote does that filing on the Mac, then hands you the draft and the
receipt for every line of it.

Step 1 — Record
  Capture the session, or dictate it after. A patient-visible strip keeps
  consent where it belongs: on the desk, not in a settings screen.

Step 2 — Transcribe
  Speech recognition runs on the Mac itself — the system's own engine. No
  download to wait for, no request to leave the room.

Step 3 — Route
  Each statement is filed into the structure your discipline actually
  documents in — DAP, BIRP, SOAP — not a generic dump.

Step 4 — Cite
  Every sentence carries the words that produced it. A quote that is not in
  the transcript does not enter the note. This step is the product.

Step 5 — Sign
  You review, correct and file. Required sections you didn't cover are named
  out loud, not hidden. The machine never signs — only you can.

========================================
SOCIAL PROOF
========================================

Not shipped. There are no testimonials, logos or benchmarks to publish, and
inventing them would contradict PRODUCT-TRUTH.md. The trust bar in the hero
carries four claims that are checkable in this repository today (see
"constraint" above). When the validation sprint lands real therapists, this
section gets real quotes with named disciplines.

========================================
FAQ
========================================

Q: Does the recording leave my Mac?
A: No. The Rust engine has no HTTP client — it is checked on every build.
   Speech recognition is the system's own SpeechAnalyzer, so listening makes
   no request either. The one download the app ever makes is the note model,
   once, on first use. Audio and notes never leave.

Q: Will it invent findings my client didn't mention?
A: It is built not to, and the refusal is mechanical rather than a promise: a
   quote must exist in the transcript or it does not enter the note, risk is
   never generated, and anything the generator cannot confidently route lands
   in an "unfiled" list for you to place — never in the bin.

Q: Is it HIPAA / GDPR compliant?
A: That has not been assessed, so it is not claimed. What is true today: no
   account, no upload, no telemetry, and the store is SQLCipher-encrypted with
   the key in your Keychain. A strong posture is not a determination.

Q: Does it integrate with my EHR?
A: Not today — output is Markdown and JSON for copy-paste into the record you
   already keep. Integration is decided by which systems paying users name.

Q: How accurate is it?
A: That has not been measured on real encounters, so no accuracy figure is
   published. The draft is exactly that — a draft, for a clinician to review
   and sign. Nothing is ever presented as final.

========================================
SUPPORT SECTION  (paid, honestly)
========================================

Framework note: the copywriter's instinct here is a three-tier price table
(Premium / Pro / Enterprise) with an SLA and a "Most Popular" badge. None
of that is built, because none of it exists. What replaced it is three cards,
one of which costs money, and none of which is a subscription — because a
subscription would be a promise the validation sprint has not earned.

See docs/product/MONETISATION.md for the reasoning; this is the copy.

Section intro:
  Left:  Help that doesn't cost you the room
  Right: A solo practitioner does not have a procurement department, so there
         is no procurement process here either. Two of these cost nothing and
         one does not, yet — the paid one is template work you can buy today,
         and the subscription comes when validation says the draft is worth one.

Card 01 — "Community support" · Free · Apache-2.0, always
  File an issue on GitHub and it is read by the person who wrote the code. The
  privacy model, the template format and the known gaps are all documented in
  the open — including the two the project names as unfunded: scoring a draft
  against a clinician-signed note, and separating two voices that sound alike.
  CTA: Open an issue

Card 02 — "Shape it for your discipline" · Free · Three to five practices
  You get the template build free — the same work that costs $600 — tuned to how
  your practice actually documents. In exchange you report honestly on the draft:
  what it invented, what it misfiled, whether reviewing it took longer than
  typing it. Those reports are the only way the defaults for your discipline get
  written by someone who has signed its notes, and that is why this one is free.
  CTA: Apply for a place

  Note on framing: this card was first written founder-first ("report what the
  draft got wrong", "the invented-finding rate gets measured") and had to be
  rewritten. Read from the clinician's side it asked for unpaid QA in exchange
  for software that is already free — the $99 problem with the payment removed.
  A cohort is genuinely needed, because GitHub issues cannot answer the roadmap's
  kill questions; but the card leads with what the practice gets and names the
  exchange as an exchange. The title is not "validation cohort": that is startup
  jargon that positions the reader as a test subject.

Card 03 — "A template built for you" · from $600 · One-off, no subscription
  For a practice whose notes do not fit a built-in shape. Your discipline's
  template is written and tuned to the way your clinicians actually document,
  tested against notes you have already signed, and handed back as a file you
  own. Deliverable with what is built today; it is template work, and it buys
  no promise about transcription.
  CTA: Commission a template

The promise that bounds all of it:
  Nothing here is a subscription yet, because a subscription would be a promise
  the validation sprint has not earned the right to make. When the cohort says
  the draft is worth standing behind, the practice tier arrives — tuned
  templates, priority triage, and a named person accountable — priced per
  practice, not per clinician. Until then the one thing money buys is a
  template, and it buys no promise about accuracy, compliance or time saved.
========================================

Not built. The Pelmatech design ships exactly three sections and adding a
fourth would mean inventing design tokens the spec forbids. When the site
grows, the honest final CTA is:

  Urgency:    Klinote is in validation with a small number of practices.
  Reversal:   If the draft puts words in a client's mouth, or reviewing it
              takes longer than typing it, stop using it and say so.
  Button:     "Request early access"

========================================
OPTIMIZATION NOTES
========================================

A/B Test Ideas:
- Headline variant: "Your session. Your Mac. Your note." (shorter, weaker on
  the specific promise — test against the positioning line, not beside it)
- CTA variant: "Start with a transcript" (lower commitment, true today: the
  plain-text path needs no model at all) vs "Request early access"
- Problem card order: lead with "Invented" rather than "Uploaded" — for
  therapists who already left a cloud scribe, the invented finding is the
  fire they name, and the disk is settled law

Conversion Tips:
- The hero trust bar must stay four checkable facts, never four adjectives.
  "Encrypted at rest" is true; "bank-grade security" would be noise.
- Keep "the machine never signs" visible. It is the one sentence that a
  therapist reading a cloud-scribe comparison page is looking for.
- Do not add a pricing table. Pricing beyond the validation offer is
  undecided in PRODUCT-TRUTH.md; a price published now would be fiction.
- Do not soften "not assessed" answers in the FAQ. The directness is the
  positioning — a therapist who reads "that has not been measured" and stays
  is the therapist this product is for.
```

## Section order (revised — PAS, not the template's)

The template's order was solution-first: Hero → How it works → The cost.
That is AIDA, not the PAS this page is written in. Reordered to:

    Hero (the promise) → The cost (problem + agitate) → How it works
    (solution) → Support (the offer) → FAQ (objections) → Final CTA

The final CTA did not exist — a convinced reader reached a footnote instead
of an action. It closes on the brand ink (#16324F, DESIGN.md's ink token,
the same ground as the OG card): heading "See if the draft is one you would
have signed", both actions, and the one real limit stated as a real limit.

The carousel steps carried no descriptions — five one-word labels; the step
copy below existed in this file and was never implemented. Now rendered.

Declined from the framework, deliberately: testimonials (none exist),
"proven / guaranteed / effortless" (nothing is proven or measured), and
invented scarcity (the 3–5 cohort cap is the only real limit, so it is the
only one used).

## Design → copy mapping

| Pelmatech (template) | Klinote (this page) | Why |
|---|---|---|
| "Your Personal Health Companion" | "The session stays in the room. The note still gets written." | Canonical positioning from PRODUCT-TRUTH.md, 10 words |
| Team carousel, 5 doctors | "How it works", 5 steps | There is no team to photograph and no permission to invent one. The carousel mechanism is preserved exactly; the cards carry workflow steps. |
| Benefits cards: Unavailable / Unethical / Waitlist | Problem cards: Uploaded / Invented / Untraceable | The template's negative-card framing *is* PAS agitation. Swapped in real Klinote problems. |
| Logo swap on scroll | Kept, with a Klinote wordmark | Lowercase sans wordmark per PRODUCT.md — no rule, no serif, no domain line |
| (none — template has no such section) | Support section, 3 cards | New, not from the template. Added because a stuck clinician is the moment to pitch. Three cards, not three tiers, because only one paid offering is honest today: a one-off template build. |
