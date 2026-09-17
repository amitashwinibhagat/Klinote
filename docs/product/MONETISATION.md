# Monetisation — the plan

Last updated: 2026-09-17 · Status: **decided, Stage 0 in effect**

This is the plan, now acted on. It sits beside `PRODUCT-TRUTH.md` (what is true)
and `ROADMAP.md` (what happens next); where those two disagree with it, they
win. Pricing beyond the validation offer was **undecided** in `PRODUCT.md` —
this document is the decision, and the reasoning that got there.

## Decisions made

| Question | Decision | Reasoning |
|---|---|---|
| Free or paid validation? | **Free** | Charging for the privilege of being a test subject selects the wrong testers. The findings are worth more than $99 a month × three practices. |
| What is sellable today? | **A bespoke template build, from $600, one-off** | Deliverable with what is built; does not depend on unproven ASR accuracy; every build is itself a validation conversation. It is the one paid offer that does not require a lie. |
| Per practice, per seat, or one-off? | **One-off now; per practice when the tier opens** | A subscription cannot be sold before validation. The one-off is the doorway that funds a conversation instead of competing with one. |
| Is $199/month defensible? | **Not yet — held back** | Unknown until three practices accept the *shape*. The number is not tuned before then. |
| What happens to the $99/month offer? | **Replaced** | No takers, nothing to honour, nothing to migrate. |

---

## The diagnosis: what is wrong with the $99/month validation practice

Four faults, each independent of the others.

**1. It is upside down.** The clinician pays $99 a month *and* does the work:
runs real sessions, reports what the draft got wrong, supplies already-signed
notes to measure the invented-finding rate against. In any normal validation the
founder pays the tester, or at minimum does not charge them. Charging a clinician
for the privilege of being a test subject selects for people who like early
access more than they like a working product — which is exactly the wrong group
to tell you whether the thing has a job.

**2. It sells the wrong thing to the wrong buyer.** It is pitched at an
individual therapist who wants "the draft shaped to the way they document." But
the person who feels the cost of inconsistent, indefensible documentation is the
*practice*, and the person who can approve spend is the practice manager. A
clinician with a free Apache-2.0 app on their own Mac has no procurement reason
to send $99 a month anywhere.

**3. The scarcity is manufactured, and a buyer can tell.** "A handful of
practices, while it lasts" creates urgency for a product nobody has validated
yet. Scarcity that reads as a launch tactic on a product that has not launched
is worse than no scarcity at all — it costs the trust the whole positioning is
built to earn.

**4. It does not survive validation failure.** `ROADMAP.md` has kill criteria:
if reviewing the draft takes longer than typing it, or five of ten will not
capture a session, there is no job. Having taken $99 a month from practices
before that is known means refunding and apologising on the way out. Validate
first, charge only what survived.

It is also founder-time-bound: each practice needs template tuning and
measurement, so $99 a month is a loss leader that consumes the entire support
capacity and crowds out the ten conversations the roadmap actually requires.

**Cost of changing it: nothing.** The offer went up this week. There are no
paying practices to offend and no terms to honour.

---

## What can be sold today

Honest inventory — each item is real and deliverable with what is built:

- **A template tuned to how a practice actually documents.** Cue editing in
  TOML, no code. `templates/*.toml` and `TemplateLibrary::BUILTIN` are the whole
  surface. Deliverable today.
- **Accountability.** Priority triage and a named human when the draft is wrong.
  Nothing else in the category sells this, because the cloud vendors cannot.
- **The local-only guarantee.** Free, and it is the entire reason a therapist
  would leave Upheal, Mentalyc or Heidi. It is the funnel, not the product.
- **A notarised build and the CLI concierge path** (paste a transcript, get a
  note, no model, no account).

## What cannot be sold today

| Cannot sell | Why |
|---|---|
| Time saved | Not measured on real encounters. This is precisely what validation measures. |
| Accuracy / clinical validity | Tested against synthetic fixtures only. |
| Compliance (HIPAA / GDPR) | Never assessed. A posture is not a determination. |
| EHR integration | Does not exist; output is Markdown/JSON. |
| Multi-seat practice tooling | No shared practice config exists. |
| Retention and deletion controls | Not built. |

---

## The model: free now, price on proof

**Stage 0 — validation is free, not a paid beta (now → the green light).**

Three to five practices get everything free, template tuning included, in
exchange for real sessions and the right to publish anonymised findings. The
founder pays in time; the practice pays nothing. This is cheaper than $99 a
month *and* it removes the filter that selects the wrong testers. The roadmap's
kill criteria apply unchanged. Money changes hands only if a practice wants to
keep the tuned template after the cohort ends — at which point it is a purchase,
not a subscription to a beta.

**Stage 1 — a Practice tier, priced per practice (on the green light).**

Solo clinicians stay free forever; the app is Apache-2.0 and that cannot change.
The practice buys:

- templates built and tuned to its note shapes
- priority triage on wrong drafts
- a named person accountable for the draft

This is the OSS economics applied honestly: free for the person, paid for the
organisation. The free individual app is the trojan horse; the practice is where
procurement lives and where the pain is felt.

**Stage 2 — only with a named ask.** EHR-shaped paste, retention controls,
site deployment. Priced when a paying practice names the need — which is already
how `ROADMAP.md` decides those features. Nothing here is invented; the trigger
table already implies it.

**Feature sponsorship, as a third path.** A practice that needs the SimplePractice
or Jane-shaped paste commissions the build and pays for it. The roadmap already
gates integration on "≥ 2 paying users name the same system," so this is not a
new idea — it is the same one with a price on it.

---

## Pricing options

| Option | Unit | Suggested | Works because | Fails because |
|---|---|---|---|---|
| **A. Per practice** | practice / month | $199 | Matches procurement; simple yes/no; no per-seat counting | A 2-person practice pays the same as a 10-person one, which they notice |
| **B. Per seat** | clinician / month | $39, 2-seat minimum | Scales with the practice; easy to justify internally | Counting seats is admin nobody wants; invites seat-hiding |
| **C. One-off build** | per template build | $600–900, +$79/mo to keep tuning | Cash now; converts validation work into a product; no recurring commitment to justify | Does not compound; still founder time |
| **D. Sponsored feature** | per build | cost + margin | Funds exactly the roadmap's next item; the ask is concrete | One-off; the practice owns the priority |

**Recommendation: A (per practice, $199/month) as the headline, with C (one-off
build) as the low-commitment doorway in.** A practice manager can say yes to A in
one conversation and explain it to a partner in one sentence. C catches the
practice that has budget for a project but not a subscription — and a
surprising share of C buyers convert to A once the template is live and they
want it maintained.

The specific number is arguable and should be argued *after* three practices have
said the shape is right. The unit is the decision; the price is a detail.

**Capacity reality.** A solo founder can support roughly five to eight practices
well. At $199 that is $1.0–1.6k a month — real money, not a livelihood. Stage 1's
purpose is **proof that anyone will pay**, which is what justifies going
full-time or raising money, not the rent. This is the one number here that is not
arguable: the plan must be honest about what it is for.

---

## What changes on the website

Done. The Support section now carries three cards and no paid beta:

1. **Community support — free.** GitHub issues, the privacy model, the named gaps.
2. **The validation cohort — free.** Apply, run real sessions, pay nothing. This
   replaced the $99/month card.
3. **A template built for you — from $600, one-off.** The honest paid doorway:
   template work, deliverable today, no promise about transcription.

The "while it lasts" line is gone, along with the fake scarcity. The practice

tier is named as the direction, not as something you can buy.

The README's Support section was rewritten to match, and now points here for the
reasoning rather than restating it — the two drifted apart once already, over
exactly this.

---

## Decisions needed

Made, and recorded in the table above. The one that stays open: **the price of
the template build**. `from $600` is a floor chosen to be defensible rather than
optimised — if three practices say yes at that number it is right; if they flinch
at the shape rather than the figure, it is the shape that is wrong, not the price.

---

## What this plan does not do

- It does not propose a cloud tier. Local-only is the product's entire reason to
  exist; a hosted version is a different company.
- It does not propose selling anonymised data, insights, or benchmarks. No
  patient data leaves the Mac, and the trust that buys is worth more than any
  aggregate product.
- It does not claim compliance, accuracy, or time saved, because none of those
  are measured. When validation produces numbers, those numbers become the
  pricing argument — and not before.
