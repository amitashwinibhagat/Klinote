import re

# ---------- index.tsx ----------
p = 'routes/index.tsx'
s = open(p).read()

edits = [
    # --- hero sub ---
    (
        """Klinote turns a session — recorded or dictated — into a
                  structured progress-note draft entirely on your Mac. Every
                  sentence cites the words that produced it. Nothing is uploaded —
                  there is nothing to upload to.""",
        """Klinote turns a session, recorded or dictated, into a
                  structured progress-note draft entirely on your Mac. Every
                  sentence cites the words that produced it. Nothing is uploaded,
                  because there is nothing to upload to."""
    ),

    # --- cost card 01 ---
    (
        """A cloud scribe means the session exists on a vendor’s disk before the note exists. Licence, ethics, or law says the room stays in the room — and the recording leaves before the note is written.""",
        """A cloud scribe means the session sits on a vendor’s disk before the note does. Licence, ethics or law may say the room stays in the room, and the recording leaves first."""
    ),

    # --- cost card 02 (triple becomes a list, not a chant) ---
    (
        """A draft that puts words in the client’s mouth is worse than no draft: a risk they did not name, a feeling they did not describe, a plan they did not agree to. You cannot sign that — and you should not have to rewrite it either.""",
        """A draft that puts words in the client’s mouth is worse than no draft: a risk they did not name, a feeling they did not describe, and a plan they did not agree to. You cannot sign that, and you should not have to rewrite it either."""
    ),

    # --- cost card 03 (drop "the only honest question", straight quotes) ---
    (
        """When a sentence arrives with no source, the only honest question is “why is this in my note?” — and “the model said so” is not an answer a record accepts.""",
        """When a sentence arrives with no source, the question "why is this in my note?" has no answer a record accepts."""
    ),

    # --- support intro ---
    (
        """A solo practitioner does not have a procurement department, so there is
            no procurement process here either. Two of these cost nothing and one
            does not, yet — the paid one is template work you can buy today, and
            the subscription comes when validation says the draft is worth one.""",
        """A solo practitioner does not have a procurement department, so there is
            no procurement process here. Two of these cost nothing. The third is
            template work you can buy today, and the subscription comes later, if
            validation earns it."""
    ),

    # --- support card 01 ---
    (
        """File an issue on GitHub and it is read by the person who wrote the code. The privacy model, the template format and the known gaps are all documented in the open — including the two the project names as unfunded: scoring a draft against a clinician-signed note, and separating two voices that sound alike.""",
        """File an issue on GitHub and the person who wrote the code reads it. The privacy model, the template format and the known gaps are documented in the open, including the two the project names as unfunded: scoring a draft against a clinician-signed note, and separating two voices that sound alike."""
    ),

    # --- support card 02 ---
    (
        """You get the template build free — the same work that costs $600 — tuned to how your practice actually documents. In exchange you report honestly on the draft: what it invented, what it misfiled, whether reviewing it took longer than typing it. Those reports are the only way the defaults for your discipline get written by someone who has signed its notes, and that is why this one is free.""",
        """You get the template build free, the same work that costs $600, tuned to how your practice documents. In exchange you report honestly on the draft: what it invented, what it misfiled, and whether reviewing it took longer than typing it. Those reports are how the defaults for your discipline get written by someone who has signed its notes. That is why this one is free."""
    ),

    # --- support card 03 ---
    (
        """For a practice whose notes do not fit a built-in shape. Your discipline\\u2019s template is written and tuned to the way your clinicians actually document, tested against notes you have already signed, and handed back as a file you own. Deliverable with what is built today; it is template work, and it buys no promise about transcription.""",
        """For a practice whose notes do not fit a built-in shape. Your template is written and tuned to the way your clinicians document, tested against notes you have already signed, and handed back as a file you own. It is template work, and it buys no promise about transcription."""
    ),

    # --- support closing ---
    (
        """Nothing here is a subscription yet, because a subscription would be a
        promise the validation sprint has not earned the right to make. When the
        cohort says the draft is worth standing behind, the practice tier arrives
        — tuned templates, priority triage, and a named person accountable —
        priced per practice, not per clinician. Until then the one thing money
        buys is a template, and it buys no promise about accuracy, compliance or
        time saved.""",
        """Nothing here is a subscription yet. A subscription would promise more
        than the validation sprint can support. When the cohort says the draft is
        worth standing behind, the practice tier arrives: tuned templates,
        priority triage, and a named person accountable, priced per practice.
        Until then the one thing money buys is a template, and it buys no promise
        about accuracy, compliance or time saved."""
    ),

    # --- FAQ intro (curly quotes) ---
    (
        """Ask these of any scribe. The answers here are the ones that are true
            today, including the ones that are still “not yet measured”.""",
        """Ask these of any scribe. The answers here are the ones that are true
            today, including the ones that are still "not yet measured"."""
    ),

    # --- FAQ a1 ---
    (
        """No. The Rust engine has no HTTP client — it is checked on every build.""",
        """No. The Rust engine has no HTTP client, and that is checked on every build."""
    ),

    # --- FAQ a2 ---
    (
        """It is built not to, and the refusal is mechanical rather than a promise: a quote must exist in the transcript or it does not enter the note, risk is never generated, and anything the generator cannot confidently route lands in an “unfiled” list for you to place — never in the bin.""",
        """It is built not to, and the refusal is mechanical rather than a promise: a quote must exist in the transcript or it does not enter the note, risk is never generated, and anything the generator cannot confidently route lands in an "unfiled" list for you to place. Nothing goes to the bin."""
    ),

    # --- FAQ a4 ---
    (
        """Not today — output is Markdown and JSON for copy-paste into the record you already keep.""",
        """Not today. Output is Markdown and JSON for copy-paste into the record you already keep."""
    ),

    # --- FAQ a5 ---
    (
        """That has not been measured on real encounters, so no accuracy figure is published. The draft is exactly that — a draft, for a clinician to review and sign. Nothing is ever presented as final.""",
        """That has not been measured on real encounters, so no accuracy figure is published. The draft is exactly that: a draft, for a clinician to review and sign. Nothing is ever presented as final."""
    ),

    # --- FAQ closing line ---
    (
        """<span className="font-mono">Klinote {appVersion}</span> for macOS is free to try, notarized, and
           {' '}
            <a
              href={downloadUrl}
              className="text-foreground underline underline-offset-4 decoration-border hover:decoration-foreground transition"
            >
              downloadable directly from GitHub
            </a>
            . No account, no sign-up, no telemetry — ever.""",
        """<span className="font-mono">Klinote {appVersion}</span> for macOS is free to try, notarized, and
           {' '}
            <a
              href={downloadUrl}
              className="text-foreground underline underline-offset-4 decoration-border hover:decoration-foreground transition"
            >
              downloadable directly from GitHub
            </a>
            . There is no account to create and no telemetry to switch off."""
    ),

    # --- final CTA scarcity line ---
    (
        """Three to five cohort places — a real limit, not a launch tactic""",
        """Three to five cohort places. That limit is real."""
    ),
]

for old, new in edits:
    if old not in s:
        raise SystemExit("NOT FOUND in index.tsx:\n" + old[:120])
    s = s.replace(old, new)
open(p, 'w').write(s)
print("index.tsx: %d edits applied" % len(edits))

# ---------- TeamCarousel.tsx ----------
p2 = 'components/TeamCarousel.tsx'
t = open(p2).read()

step_edits = [
    (
        """Capture the session, or dictate it after. A patient-visible strip keeps consent where it belongs — on the desk, not in a settings screen.""",
        """Capture the session, or dictate it after. The patient can see that recording is happening, because consent does not belong in a settings screen."""
    ),
    (
        """Speech recognition runs on the Mac itself — the system’s own engine. No download to wait for, no request to leave the room.""",
        """Speech recognition runs on the Mac with the system’s own engine. Nothing downloads, and nothing leaves the room."""
    ),
    (
        """Each statement is filed into the structure your discipline actually documents in — DAP, BIRP, SOAP — not a generic dump.""",
        """Each statement is filed into the structure your discipline documents in, whether that is DAP, BIRP or SOAP."""
    ),
    (
        """Every sentence carries the words that produced it, and a quote that is not in the transcript does not enter the note. This step is the product.""",
        """Every sentence carries the words that produced it. A quote that is not in the transcript does not enter the note. This step is the product."""
    ),
    (
        """You review, correct and file. Required sections you did not cover are named out loud, not hidden. The machine never signs — only you can.""",
        """You review, correct and file. Required sections you did not cover are named in the open. The machine never signs. Only you can."""
    ),
]

for old, new in step_edits:
    if old not in t:
        raise SystemExit("NOT FOUND in TeamCarousel.tsx:\n" + old[:120])
    t = t.replace(old, new)
open(p2, 'w').write(t)
print("TeamCarousel.tsx: %d edits applied" % len(step_edits))
