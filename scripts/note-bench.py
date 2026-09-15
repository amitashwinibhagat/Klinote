#!/usr/bin/env python3
"""Score Klinote's note-writing path on the SOAP job.

The note is written by Apple's on-device model through the Foundation Models
framework, so there is no GGUF to fetch and no second model to compare against:
this scores the one engine the product ships, on the fixture the product uses.

It compiles `apps/Klinote/Bench/note-bench.swift` with swiftc — Sources/Domain
plus NoteDrafter, no app, no FFI, no Keychain — and pipes the request in.

  python3 scripts/note-bench.py
  python3 scripts/note-bench.py --transcript fixtures/sample-transcript.txt

Needs macOS 26 with Apple Intelligence available. Writes fixtures/note-bench/last-report.json.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GOLD = ROOT / "fixtures/note-bench/gold-facts.json"
DEFAULT_TRANSCRIPT = ROOT / "fixtures/sample-transcript.txt"
BENCH_SOURCE = ROOT / "apps/Klinote/Bench/note-bench.swift"
DOMAIN = ROOT / "apps/Klinote/Sources/Domain"
NOTEDRAFTER = ROOT / "apps/Klinote/Sources/Core/NoteDrafter.swift"
BINARY = Path("/tmp/klinote-note-bench")
HEADER = ROOT / "crates/scribe-ffi/include/scribe_core_ffi.h"
LINK_DIR = ROOT / "target/klinote-link"

# Apple's on-device model is a system API, so the harness has to be built for a
# deployment target that has it. Domain is Foundation-only, which is what makes
# this possible without the app.
MACOS_TARGET = "arm64-apple-macos26.0"


def parse_transcript(text: str) -> dict:
    encounter_id = str(uuid.uuid4())
    speakers = [
        {"id": 0, "role": "clinician", "label": None},
        {"id": 1, "role": "patient", "label": None},
    ]
    segments = []
    cursor_ms = 0
    role_ids = {"clinician": 0, "patient": 1}
    last_role = "clinician"
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        role, body = last_role, line
        if ":" in line:
            head, tail = line.split(":", 1)
            key = head.strip().lower()
            if key in role_ids:
                role, body = key, tail.strip()
        last_role = role
        if not body:
            continue
        est = min(30_000, max(400, len(body.split()) * 400))
        segments.append(
            {
                "id": str(uuid.uuid4()),
                "speaker": role_ids.get(role, 0),
                "start_ms": cursor_ms,
                "end_ms": cursor_ms + est,
                "text": body,
                "confidence": None,
            }
        )
        cursor_ms += est + 200
    return {
        "encounter_id": encounter_id,
        "speakers": speakers,
        "segments": segments,
        "language": "en",
        "engine": "bench-human",
        "created_at": "2026-09-11T12:00:00Z",
        "human_supplied": True,
    }


def soap_template() -> dict:
    return {
        "id": "soap",
        "name": "SOAP Note",
        "sections": [
            {"key": "subjective", "title": "Subjective", "required": True},
            {"key": "objective", "title": "Objective", "required": True},
            {"key": "assessment", "title": "Assessment", "required": True},
            {"key": "plan", "title": "Plan", "required": True},
        ],
    }


def _display_path(path: Path) -> str:
    """Relative where it is inside the repo, absolute where it is not.

    A path given on the command line may be either, and `relative_to` raises on
    the second rather than saying so.
    """
    resolved = path.resolve()
    return str(resolved.relative_to(ROOT)) if resolved.is_relative_to(ROOT) else str(resolved)


def build_request(transcript_path: Path) -> dict:
    return {
        "transcript": parse_transcript(transcript_path.read_text()),
        "template": soap_template(),
    }


def build_bench() -> None:
    """Compile Domain + NoteDrafter + the harness against the real engine.

    The engine is linked in because the template — with its `guidance` and
    `cues` — comes from `scribe_list_templates`, the same call the app makes.
    Building the template by hand left those empty, which pointed the drafter at
    fields it had been told nothing about and measured a prompt the app never
    sends.

    Rebuilt whenever a source or the library is newer than the binary, so a
    change to the prompts is measured rather than assumed.
    """
    static_lib = LINK_DIR / "libscribe_core_ffi.a"
    if not static_lib.exists():
        print("building the engine (release)…")
        subprocess.check_call(["cargo", "build", "--release", "-p", "scribe-ffi"], cwd=ROOT)
        LINK_DIR.mkdir(parents=True, exist_ok=True)
        subprocess.check_call(
            ["cp", "target/release/libscribe_core_ffi.a", str(LINK_DIR)], cwd=ROOT
        )

    sources = sorted(DOMAIN.glob("*.swift")) + [NOTEDRAFTER, BENCH_SOURCE]
    if BINARY.exists() and all(
        p.stat().st_mtime <= BINARY.stat().st_mtime for p in sources + [static_lib]
    ):
        return
    print("building the on-device bench…")
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
        sys.stderr.write(proc.stderr[-2000:])
        raise SystemExit("could not build the bench harness")


def run_bench(request: dict, timeout: int) -> tuple[dict | None, str, float]:
    import time

    t0 = time.time()
    try:
        proc = subprocess.run(
            [str(BINARY)],
            input=json.dumps(request).encode(),
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, "timeout", time.time() - t0
    elapsed = time.time() - t0

    stdout = proc.stdout.decode("utf-8", "replace").strip()
    if not stdout:
        err = proc.stderr.decode("utf-8", "replace")[-400:]
        return None, f"exit {proc.returncode}: {err}", elapsed
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return None, "stdout was not JSON", elapsed
    if not payload.get("ok"):
        err = payload.get("error") or "ok=false"
        (ROOT / "fixtures/note-bench" / "last-fail.txt").write_text(err)
        return None, err, elapsed
    return payload.get("note"), "", elapsed


def score(note: dict, request: dict, gold: dict) -> dict:
    sections = note.get("sections") or []
    required = [s for s in request["template"]["sections"] if s.get("required")]
    filled_required = 0
    sentences = []
    for section in sections:
        body = (section.get("body") or "").strip()
        spec = next((s for s in required if s["key"] == section.get("key")), None)
        if spec and body:
            filled_required += 1
        for sent in section.get("sentences") or []:
            sentences.append(sent)

    # evidence arrays on the note are segment UUIDs after assemble
    valid_ids = {seg["id"] for seg in request["transcript"]["segments"]}
    evidence_ok = 0
    evidence_total = 0
    for sent in sentences:
        ids = sent.get("evidence") or []
        evidence_total += len(ids)
        evidence_ok += sum(1 for i in ids if i in valid_ids)

    blob = " ".join((section.get("body") or "") for section in sections).lower()
    must = gold.get("must_appear") or []
    must_not = gold.get("must_not_appear") or []
    hits = [f for f in must if f.lower() in blob]
    leaks = [f for f in must_not if f.lower() in blob]

    return {
        "required_filled": f"{filled_required}/{len(required)}",
        "required_ok": filled_required == len(required),
        "sentences": len(sentences),
        "evidence_precision": round(evidence_ok / evidence_total, 3) if evidence_total else 0.0,
        "gold_recall": round(len(hits) / len(must), 3) if must else 0.0,
        "gold_hits": hits,
        "gold_misses": [f for f in must if f not in hits],
        "parking_leaked": bool(leaks),
        "unassigned": len(note.get("unassigned") or []),
        "missing_required": note.get("missing_required") or [],
        "utterances": len(request["transcript"]["segments"]),
        "engine": note.get("engine"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript", type=Path, default=DEFAULT_TRANSCRIPT)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()

    gold = json.loads(GOLD.read_text())
    request = build_request(args.transcript)
    build_bench()

    note, err, elapsed = run_bench(request, args.timeout)
    if note is None:
        print(f"FAIL {err}")
        return 1

    result = score(note, request, gold)
    result["seconds"] = round(elapsed, 2)
    result["transcript"] = _display_path(args.transcript)

    out = ROOT / "fixtures/note-bench" / "last-note.json"
    out.write_text(json.dumps({"note": note, "score": result}, indent=2))

    print(f"\ntranscript   {result['transcript']}  ({result['utterances']} utterances)")
    print(f"engine       {result['engine']}")
    print(f"seconds      {result['seconds']}")
    print(f"required     {result['required_filled']}")
    print(f"sentences    {result['sentences']}")
    print(f"evidence     {result['evidence_precision']}")
    print(f"gold recall  {result['gold_recall']}  misses={result['gold_misses']}")
    print(f"leak         {'YES' if result['parking_leaked'] else 'no'}")
    print(f"unfiled      {result['unassigned']}")
    if result["missing_required"]:
        print(f"missing      {result['missing_required']}")
    print(f"\nWrote {out}")
    print("Want: required 4/4, evidence 1.00, parking leak no.")
    print("Gold recall is literal ('four days' vs '4 days') — read the note, not just the score.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
