#!/usr/bin/env python3
"""Score small local GGUFs on Nota's SOAP job.

Same extract→refine pipeline (`scribe-llm`) for every model. No network in the
Rust engine; this script may download catalog GGUFs when you pass --download.

  python3 scripts/note-bench.py
  python3 scripts/note-bench.py --download
  python3 scripts/note-bench.py --models-dir ~/Library/Application\\ Support/Nota/Models
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "fixtures/note-bench/catalog.json"
GOLD = ROOT / "fixtures/note-bench/gold-facts.json"
TRANSCRIPT = ROOT / "fixtures/sample-transcript.txt"
DEFAULT_MODELS = Path.home() / "Library/Application Support/Nota/Models"


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


def build_request() -> dict:
    return {
        "transcript": parse_transcript(TRANSCRIPT.read_text()),
        "template": soap_template(),
    }


def download(url: str, dest: Path, expected: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size >= expected * 0.98:
        print(f"  have {dest.name} ({dest.stat().st_size} bytes)")
        return
    print(f"  downloading {dest.name} …")
    tmp = dest.with_suffix(dest.suffix + ".part")
    urllib.request.urlretrieve(url, tmp)
    tmp.rename(dest)
    print(f"  saved {dest.stat().st_size} bytes")


def score(note: dict, request: dict, gold: dict) -> dict:
    n_utt = len(request["transcript"]["segments"])
    sections = note.get("sections") or []
    required = [s for s in request["template"]["sections"] if s.get("required")]
    filled_required = 0
    sentences = []
    cited = []
    for section in sections:
        body = (section.get("body") or "").strip()
        spec = next((s for s in required if s["key"] == section.get("key")), None)
        if spec and body:
            filled_required += 1
        for sent in section.get("sentences") or []:
            sentences.append(sent)
            cited.extend(sent.get("evidence") or [])

    # evidence arrays on the note are UUIDs after assemble
    valid_ids = {seg["id"] for seg in request["transcript"]["segments"]}
    evidence_ok = 0
    evidence_total = 0
    for sent in sentences:
        ids = sent.get("evidence") or []
        evidence_total += len(ids)
        evidence_ok += sum(1 for i in ids if i in valid_ids)

    blob = " ".join(
        (section.get("body") or "") for section in sections
    ).lower()
    must = gold.get("must_appear") or []
    must_not = gold.get("must_not_appear") or []
    hits = [f for f in must if f.lower() in blob]
    leaks = [f for f in must_not if f.lower() in blob]

    unassigned = note.get("unassigned") or []
    missing = note.get("missing_required") or []

    return {
        "json_ok": True,
        "required_filled": f"{filled_required}/{len(required)}",
        "required_ok": filled_required == len(required),
        "sentences": len(sentences),
        "evidence_precision": round(evidence_ok / evidence_total, 3) if evidence_total else 0.0,
        "gold_recall": round(len(hits) / len(must), 3) if must else 0.0,
        "gold_hits": hits,
        "gold_misses": [f for f in must if f not in hits],
        "parking_leaked": bool(leaks),
        "unassigned": len(unassigned),
        "missing_required": missing,
        "utterances": n_utt,
        "engine": note.get("engine"),
    }


def run_model(binary: Path, model: Path, request: dict, timeout: int) -> tuple[dict | None, str, float]:
    t0 = time.time()
    try:
        proc = subprocess.run(
            [str(binary), "--model", str(model)],
            input=json.dumps(request).encode(),
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, "timeout", time.time() - t0
    elapsed = time.time() - t0
    if proc.returncode != 0 and not proc.stdout:
        err = proc.stderr.decode("utf-8", "replace")[-400:]
        return None, f"exit {proc.returncode}: {err}", elapsed
    try:
        payload = json.loads(proc.stdout.decode())
    except json.JSONDecodeError:
        return None, "stdout was not JSON", elapsed
    if not payload.get("ok"):
        err = payload.get("error") or "ok=false"
        (ROOT / "fixtures/note-bench" / "last-fail.txt").write_text(err)
        return None, err, elapsed
    return payload.get("note"), "", elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models-dir", type=Path, default=DEFAULT_MODELS)
    parser.add_argument("--download", action="store_true", help="fetch catalog GGUFs that are missing")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--only", action="append", help="catalog id to run (repeatable)")
    parser.add_argument("--band", help="catalog band, e.g. sub-1gb or 1-2gb")
    args = parser.parse_args()

    catalog = json.loads(CATALOG.read_text())
    gold = json.loads(GOLD.read_text())
    request = build_request()
    models = catalog["models"]
    if args.band:
        models = [m for m in models if m.get("band") == args.band]
    if args.only:
        models = [m for m in models if m["id"] in args.only]
    if not models:
        print("no catalog ids matched filters", file=sys.stderr)
        return 2

    args.models_dir.mkdir(parents=True, exist_ok=True)
    if args.download:
        print("Downloading catalog models into", args.models_dir)
        for m in models:
            download(m["url"], args.models_dir / m["file"], m["bytes"])

    binary = ROOT / "target/release/scribe-llm"
    if not binary.exists():
        print("building scribe-llm (release)…")
        subprocess.check_call(["cargo", "build", "--release", "-p", "scribe-llm"], cwd=ROOT)

    rows = []
    print(f"\n{'model':28} {'sec':>6} {'req':>5} {'ev':>5} {'gold':>5} leak  notes")
    print("-" * 78)
    for m in models:
        path = args.models_dir / m["file"]
        if not path.exists():
            print(f"{m['id']:28} {'—':>6} skip (missing GGUF; pass --download)")
            rows.append({"id": m["id"], "skipped": True})
            continue
        note, err, elapsed = run_model(binary, path, request, args.timeout)
        if note is None:
            print(f"{m['id']:28} {elapsed:6.1f} FAIL {err[:40]}")
            rows.append({"id": m["id"], "error": err, "seconds": round(elapsed, 2)})
            continue
        s = score(note, request, gold)
        s["id"] = m["id"]
        s["seconds"] = round(elapsed, 2)
        leak = "YES" if s["parking_leaked"] else "no"
        print(
            f"{m['id']:28} {elapsed:6.1f} {s['required_filled']:>5} "
            f"{s['evidence_precision']:5.2f} {s['gold_recall']:5.2f} {leak:4} "
            f"unfiled={s['unassigned']}"
        )
        out = args.models_dir / f"bench-{m['id']}.json"
        out.write_text(json.dumps({"note": note, "score": s}, indent=2))
        rows.append(s)

    report = ROOT / "fixtures/note-bench/last-report.json"
    report.write_text(json.dumps(rows, indent=2))
    print(f"\nWrote {report}")
    print("Higher gold recall + evidence precision, required 4/4, parking leak = no.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
