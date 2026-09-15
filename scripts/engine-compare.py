#!/usr/bin/env python3
"""Quire versus the Apple Intelligence model, on the same transcript.

Two engines can write a Klinote note:

  · **Quire** — `scribe-llm`, Qwen3-4B Instruct, 1.89 GB, llama.cpp, a sibling
    process. Downloaded once. The production baseline.
  · **Apple** — `NoteDrafter`, the system on-device model through Foundation
    Models, in-process. No download. The fallback.

Both are handed *the same* transcript and *the same* template and scored by the
same rules, so the only variable is the engine.

  python3 scripts/engine-compare.py
  python3 scripts/engine-compare.py --audio /tmp/klinote-diarize/two.wav

`--audio` runs the whole chain first — recognition with `SpeechAnalyzer`,
diarisation in the Rust core — and compares the engines on what was actually
heard, recognition errors and all. Without it, both engines see the clean text
fixture, which isolates the engine from the recogniser.

Synthetic audio and text only. Never a real consultation.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/tmp/klinote-engine-compare")

# The bench already knows how to score a note and how to build a request. Import
# it rather than keeping two definitions of the same scoring rules.
_spec = importlib.util.spec_from_file_location("note_bench", ROOT / "scripts" / "note-bench.py")
note_bench = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(note_bench)

# Quire is downloaded by the app, and a sandboxed app writes into its container —
# so the file is usually under `~/Library/Containers/…`, not next to it. A CLI
# (which is unsandboxed) would see the plain path. Check both; `supportDirectory`
# in `ModelDownloader.swift` resolves to one or the other depending on who asks.
QUIRE_CANDIDATES = [
    Path.home() / "Library/Containers/one.klinote.mac/Data/Library/Application Support/Klinote/Models/quire.gguf",
    Path.home() / "Library/Application Support/Klinote/Models/quire.gguf",
]
SCRIBE_LLM = ROOT / "target/release/scribe-llm"
APPLE_BENCH = Path("/tmp/klinote-note-bench")
DIARIZE_BENCH = Path("/tmp/klinote-diarize/diarize-bench")
MACOS_TARGET = "arm64-apple-macos26.0"


def find_quire() -> Path:
    for candidate in QUIRE_CANDIDATES:
        if candidate.exists():
            return candidate
    raise SystemExit(
        "Quire is not on disk. Looked in:\n  "
        + "\n  ".join(str(p) for p in QUIRE_CANDIDATES)
        + "\nDownload it once by running the app's setup, or with:"
        + "\n  python3 scripts/note-bench.py --download   # (catalog of one)"
    )


def run(binary: Path, args: list[str], request: dict, timeout: int) -> tuple[dict | None, str, float]:
    started = time.time()
    try:
        proc = subprocess.run(
            [str(binary), *args],
            input=json.dumps(request).encode(),
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, "timeout", time.time() - started
    elapsed = time.time() - started

    stdout = proc.stdout.decode("utf-8", "replace").strip()
    if not stdout:
        return None, proc.stderr.decode("utf-8", "replace")[-300:], elapsed
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return None, "stdout was not JSON", elapsed
    if not payload.get("ok"):
        return None, str(payload.get("error"))[:300], elapsed
    return payload.get("note"), "", elapsed


def transcript_from_audio(wav: Path, timeout: int) -> dict:
    """Run the real chain and hand back what was heard.

    Recognition is the part that only exists in the app, so this reuses the
    diarisation bench — same `SpeechAnalyzer` call, same FFI, same diariser.
    """
    if not DIARIZE_BENCH.exists():
        raise SystemExit(
            f"no diarisation bench at {DIARIZE_BENCH}; run scripts/diarize-bench.py once first"
        )
    proc = subprocess.run(
        [str(DIARIZE_BENCH), str(wav)], capture_output=True, text=True, timeout=timeout
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr[-2000:])
        raise SystemExit("the recognition/diarisation chain failed")

    heard = json.loads(proc.stdout)
    segments = []
    for segment in heard["segments"]:
        segments.append(
            {
                # Quire's `Transcript` deserialises into real `Uuid` fields, so
                # these have to be UUIDs, not the readable ids that would be
                # nicer here. A plain string fails with `UUID parsing failed:
                # invalid character: found 'o'`, which names neither the field
                # nor the reason.
                "id": str(uuid.uuid4()),
                "speaker": int(segment["speaker"]),
                "start_ms": int(segment["start_ms"]),
                "end_ms": int(segment["end_ms"]),
                "text": segment["text"],
                "confidence": None,
            }
        )
    return {
        "encounter_id": str(uuid.uuid4()),
        "speakers": [
            {"id": int(s["id"]), "role": s.get("role", "other"), "label": None}
            for s in heard["speakers"]
        ],
        "segments": segments,
        "language": "en",
        "engine": heard.get("engine", "apple-speechanalyzer"),
        # The core's drug-name checks travel with the transcript, and the app's
        # do too. Dropping them here would compare the engines on a transcript
        # with less safety net than the product has.
        "name_checks": heard.get("name_checks") or [],
        "created_at": "2026-09-15T12:00:00Z",
        "human_supplied": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript", type=Path, default=ROOT / "fixtures/sample-transcript.txt")
    parser.add_argument("--audio", type=Path, help="compare on what was heard, not on clean text")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    gold = json.loads((ROOT / "fixtures/note-bench/gold-facts.json").read_text())

    quire = find_quire()
    if not SCRIBE_LLM.exists():
        raise SystemExit(f"scribe-llm is not built at {SCRIBE_LLM}")

    print("building the on-device bench…")
    note_bench.build_bench()

    if args.audio:
        print(f"running the chain over {args.audio.name}…")
        transcript = transcript_from_audio(args.audio, args.timeout)
        source = f"heard from {args.audio.name}"
    else:
        transcript = note_bench.parse_transcript(args.transcript.read_text())
        source = str(args.transcript.relative_to(ROOT))

    request = {"transcript": transcript, "template": note_bench.soap_template()}
    print(f"transcript: {source} — {len(transcript['segments'])} utterances\n")

    results: dict[str, dict] = {}
    engines = [
        # (label, binary, args)
        ("Quire 4B", SCRIBE_LLM, ["--model", str(quire)]),
        ("Apple on-device", APPLE_BENCH, []),
    ]

    for label, binary, argv in engines:
        print(f"  running {label}…", flush=True)
        note, error, seconds = run(binary, argv, request, args.timeout)
        if note is None:
            print(f"    FAILED: {error}")
            results[label] = {"error": error, "seconds": round(seconds, 1)}
            continue
        scored = note_bench.score(note, request, gold)
        scored["seconds"] = round(seconds, 1)
        results[label] = scored
        (OUT).mkdir(parents=True, exist_ok=True)
        (OUT / f"{label.split()[0].lower()}-note.json").write_text(
            json.dumps({"note": note, "score": scored}, indent=2)
        )

    print()
    header = f"{'':18}{'required':>10}{'evidence':>10}{'gold':>8}{'leak':>7}{'unfiled':>9}{'seconds':>9}"
    print(header)
    print("-" * len(header))
    for label, _binary, _argv in engines:
        row = results.get(label, {})
        if "error" in row:
            print(f"{label:18}{'FAILED: ' + row['error'][:40]:>53}")
            continue
        print(
            f"{label:18}"
            f"{row['required_filled']:>10}"
            f"{row['evidence_precision']:>10.2f}"
            f"{row['gold_recall']:>8.2f}"
            f"{'YES' if row['parking_leaked'] else 'no':>7}"
            f"{row['unassigned']:>9}"
            f"{row['seconds']:>9.1f}"
        )

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "summary.json").write_text(json.dumps(results, indent=2))
    print(f"\nWrote {OUT}")
    print("Read the notes, not the table: a score cannot see a sentence nobody said.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
