#!/usr/bin/env python3
"""Measure turn detection: does the engine put the right speaker on a segment?

`SpeechAnalyzer` reports no speaker and its ranges are contiguous, so the two
voices have to be recovered from the audio. This builds a two-voice synthesis of
the sample consultation — clinician lines in one voice, patient lines in another —
and scores what comes back against the turns it actually spoke.

The ground truth is exact: the script knows which voice said which line and when.

  python3 scripts/diarize-bench.py

Needs macOS 26 with Speech and the `say` voices Daniel and Samantha. Public and
synthetic only — never a real consultation. Writes artifacts to /tmp/klinote-diarize.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/tmp/klinote-diarize")
TRANSCRIPT = ROOT / "fixtures/sample-transcript.txt"
TRANSCRIBER = ROOT / "apps/Klinote/Sources/Core/Transcriber.swift"
BENCH_SOURCE = ROOT / "apps/Klinote/Bench/diarize-bench.swift"
HEADER = ROOT / "crates/scribe-ffi/include/scribe_core_ffi.h"
LINK_DIR = ROOT / "target/klinote-link"
BINARY = OUT / "diarize-bench"

# One voice per role. These are the two clearest opposites macOS ships.
VOICE = {"clinician": "Daniel", "patient": "Samantha"}
MACOS_TARGET = "arm64-apple-macos26.0"


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, **kwargs)


def duration_ms(path: Path) -> int:
    out = run(
        [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0", str(path),
        ]
    ).stdout.decode().strip()
    return int(float(out) * 1000)


REFRESH_AUDIO = False


def build_voice_track(source: Path, voices: dict[str, str], name: str) -> tuple[Path, list[dict]]:
    """Speak the lines with the given voices, recording who said what, when.

    Role prefixes are *not* spoken: the voices have to carry the roles, or the
    test is measuring the transcript rather than the diariser.

    `voices` maps a role to a macOS voice. Passing the *same* voice for both
    roles is the dictation case — one person, and the diariser must not invent a
    second speaker out of their ordinary variation in pitch.

    The audio and its turn timings are **cached and reused**, because `say`
    renders differently every time: a fresh synthesis each run means the
    recogniser hears slightly different words, the numbers move, and two runs
    cannot be compared. Pass `--refresh-audio` to re-synthesise deliberately.
    """
    OUT.mkdir(parents=True, exist_ok=True)
    combined = OUT / f"{name}.wav"
    truth_file = OUT / f"{name}.truth.json"

    if not REFRESH_AUDIO and combined.exists() and truth_file.exists():
        return combined, json.loads(truth_file.read_text())
    pieces: list[Path] = []
    truth: list[dict] = []
    cursor_ms = 0

    role = "clinician"
    for index, raw in enumerate(source.read_text().splitlines()):
        line = raw.strip()
        if not line:
            continue
        body = line
        if ":" in line:
            head, tail = line.split(":", 1)
            key = head.strip().lower()
            if key in voices:
                role, body = key, tail.strip()
        if not body:
            continue

        aiff = OUT / f"{name}-turn-{index:02d}.aiff"
        wav = OUT / f"{name}-turn-{index:02d}.wav"
        run(["say", "-v", voices[role], "-o", str(aiff), body])
        # 16 kHz mono PCM, which is what the recogniser and the VAD both expect.
        run(
            [
                "ffmpeg", "-y", "-loglevel", "error", "-i", str(aiff),
                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(wav),
            ]
        )
        aiff.unlink(missing_ok=True)

        ms = duration_ms(wav)
        pieces.append(wav)
        truth.append(
            {"index": index, "role": role, "start_ms": cursor_ms, "end_ms": cursor_ms + ms}
        )
        cursor_ms += ms

    truth_file.write_text(json.dumps(truth))
    listing = OUT / f"{name}-concat.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in pieces))
    run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", str(listing),
            "-c", "copy", str(combined),
        ]
    )
    for piece in pieces:
        piece.unlink(missing_ok=True)

    return combined, truth


def build_bench() -> None:
    """Compile the real path: Transcriber + the C ABI + the static engine."""
    # The binary is written into OUT, and the linker will not create the
    # directory for us: it fails with `errno=2` against the output path, which
    # reads like a missing source file rather than a missing folder.
    OUT.mkdir(parents=True, exist_ok=True)

    static_lib = LINK_DIR / "libscribe_core_ffi.a"
    if not static_lib.exists():
        print("building the engine (release)…")
        subprocess.check_call(["cargo", "build", "--release", "-p", "scribe-ffi"], cwd=ROOT)
        LINK_DIR.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(
            ["cp", "target/release/libscribe_core_ffi.a", str(LINK_DIR)], cwd=ROOT
        )

    sources = [TRANSCRIBER, BENCH_SOURCE]
    if BINARY.exists() and all(
        p.stat().st_mtime <= BINARY.stat().st_mtime for p in sources + [static_lib]
    ):
        return

    print("building the diarisation bench…")
    cmd = [
        "xcrun", "swiftc", "-O",
        "-target", MACOS_TARGET,
        "-framework", "Speech", "-framework", "AVFoundation", "-framework", "CoreMedia",
        "-framework", "Accelerate", "-framework", "Metal", "-framework", "MetalKit",
        "-import-objc-header", str(HEADER),
        "-L", str(LINK_DIR), "-lscribe_core_ffi", "-lc++",
        "-o", str(BINARY),
        *[str(p) for p in sources],
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr[-3000:])
        raise SystemExit("could not build the diarisation bench")


def true_role_at(truth: list[dict], at_ms: int) -> str | None:
    for turn in truth:
        if turn["start_ms"] <= at_ms < turn["end_ms"]:
            return turn["role"]
    return None


def score(result: dict, truth: list[dict]) -> dict:
    segments = result.get("segments") or []
    correct = 0
    scored = 0
    for segment in segments:
        midpoint = (int(segment["start_ms"]) + int(segment["end_ms"])) // 2
        expected = true_role_at(truth, midpoint)
        if expected is None:
            continue
        scored += 1
        if segment.get("role") == expected:
            correct += 1

    speakers = {segment.get("speaker") for segment in segments}
    roles = {segment.get("role") for segment in segments}

    # How many times the engine changed speaker, against how many times the
    # consultation actually did. Finding one speaker scores zero here even if
    # the accuracy looks tolerable, which is the point.
    engine_changes = 0
    previous = None
    for segment in segments:
        if previous is not None and segment.get("speaker") != previous:
            engine_changes += 1
        previous = segment.get("speaker")
    true_changes = max(len(truth) - 1, 0)

    return {
        "true_turns": len(truth),
        "transcript_segments": len(segments),
        "scored_segments": scored,
        "distinct_speakers": len(speakers),
        "distinct_roles": sorted(r for r in roles if r),
        "role_accuracy": round(correct / scored, 3) if scored else 0.0,
        "correct": correct,
        "engine_speaker_changes": engine_changes,
        "true_speaker_changes": true_changes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript", type=Path, default=TRANSCRIPT)
    parser.add_argument(
        "--refresh-audio",
        action="store_true",
        help="re-synthesise the audio instead of reusing the cached render",
    )
    args = parser.parse_args()

    global REFRESH_AUDIO
    REFRESH_AUDIO = args.refresh_audio

    print("building the bench…")
    build_bench()

    scenarios = [
        # (label, voices, expectation, slug)
        ("two voices", VOICE, "two", "two"),
        # The dictation path: one person, one voice. Inventing a second speaker
        # here would alternate a solo note's roles arbitrarily, which is worse
        # than not guessing at all.
        ("one voice (dictation)", {"clinician": "Daniel", "patient": "Daniel"}, "one", "dictation"),
        # The hard case, and the honest limit of separating voices by pitch: two
        # speakers of the same sex, close in fundamental frequency. Reported, not
        # asserted — "it works on a man and a woman" is not evidence that it
        # works in a room.
        ("two male voices (harder)", {"clinician": "Daniel", "patient": "Rishi"}, "report", "male"),
    ]

    failures: list[str] = []
    report: dict[str, Any] = {}

    for label, voices, expectation, slug in scenarios:
        print(f"\n=== {label} ===")
        audio, truth = build_voice_track(args.transcript, voices, slug)
        print(f"  {audio.name}: {duration_ms(audio) / 1000:.1f}s, {len(truth)} turns")

        proc = subprocess.run(
            [str(BINARY), str(audio)], capture_output=True, text=True, timeout=900
        )
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr[-2000:])
            return 1
        result = json.loads(proc.stdout)
        outcome = score(result, truth)
        report[label] = outcome

        print(f"  transcript segments   {outcome['transcript_segments']}")
        print(f"  distinct speakers     {outcome['distinct_speakers']}")
        print(f"  role accuracy         {outcome['role_accuracy']}  "
              f"({outcome['correct']}/{outcome['scored_segments']})")
        print(f"  speaker changes       {outcome['engine_speaker_changes']} found, "
              f"{outcome['true_speaker_changes']} real")

        if expectation == "two":
            if outcome["distinct_speakers"] != 2:
                failures.append(f"{label}: expected 2 speakers, got {outcome['distinct_speakers']}")
            if outcome["role_accuracy"] < 0.9:
                failures.append(
                    f"{label}: role accuracy {outcome['role_accuracy']} is below 0.90"
                )
        elif expectation == "one":
            if outcome["distinct_speakers"] != 1:
                failures.append(
                    f"{label}: invented {outcome['distinct_speakers']} speakers from one voice"
                )
        else:
            print("  (reported only — no pass/fail on this one)")

    (OUT / "last-result.json").write_text(json.dumps(report, indent=2))
    print(f"\nWrote {OUT / 'last-result.json'}")

    if failures:
        print("\nFAILED:")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print("\nAsserted scenarios pass: two voices are separated, one voice is not split.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
