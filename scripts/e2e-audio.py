#!/usr/bin/env python3
"""Audio → whisper → Quire SOAP. Public/synthetic audio only. Writes to /tmp/klinote-e2e."""

from __future__ import annotations

import json
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/tmp/klinote-e2e")
TRANSCRIPT = ROOT / "fixtures/sample-transcript.txt"
GOLD = ROOT / "fixtures/note-bench/gold-facts.json"
QUIRE = Path.home() / "Library/Application Support/Klinote/Models/quire.gguf"
SCRIBE = ROOT / "target/release/scribe"
LLM = ROOT / "target/release/scribe-llm"

# Public two-speaker English (1964 Beatles press conference, archive.org).
BEATLES = (
    "https://archive.org/download/BeatlesPressConference1964/BeatlesPressConference1964.mp3"
)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd[:8]), "…" if len(cmd) > 8 else "")
    return subprocess.run(cmd, check=True, **kwargs)


def say_wav(text: str, dest: Path, voice: str = "Daniel") -> None:
    aiff = dest.with_suffix(".aiff")
    run(["say", "-v", voice, "-o", str(aiff), text])
    run(
        [
            "ffmpeg", "-y", "-i", str(aiff),
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            str(dest),
        ],
        capture_output=True,
    )
    aiff.unlink(missing_ok=True)


def two_voice_consult(dest: Path) -> None:
    parts = []
    role_voice = {"clinician": "Daniel", "patient": "Samantha"}
    last = "clinician"
    for i, raw in enumerate(TRANSCRIPT.read_text().splitlines()):
        line = raw.strip()
        if not line:
            continue
        role, body = last, line
        if ":" in line:
            head, tail = line.split(":", 1)
            key = head.strip().lower()
            if key in role_voice:
                role, body = key, tail.strip()
        last = role
        if not body:
            continue
        piece = OUT / f"turn-{i:02d}.wav"
        say_wav(body, piece, role_voice[role])
        parts.append(piece)
    listing = OUT / "concat.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts))
    run(
        ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(dest)],
        capture_output=True,
    )
    for p in parts:
        p.unlink(missing_ok=True)


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


def llm_request(transcript: dict) -> dict:
    return {"transcript": transcript, "template": soap_template()}


def score(note: dict, gold: dict) -> dict:
    blob = " ".join((s.get("body") or "") for s in note.get("sections") or []).lower()
    must = gold.get("must_appear") or []
    hits = [f for f in must if f.lower() in blob]
    leak = "parking" in blob
    filled = sum(1 for s in note.get("sections") or [] if (s.get("body") or "").strip())
    return {
        "required": f"{filled}/4",
        "gold": round(len(hits) / len(must), 2) if must else 0,
        "hits": hits,
        "parking": leak,
        "unfiled": len(note.get("unassigned") or []),
        "engine": note.get("engine"),
    }


def transcribe(wav: Path, tag: str) -> dict:
    note_path = OUT / f"{tag}-rules.json"
    tr_path = OUT / f"{tag}-transcript.json"
    run(
        [
            str(SCRIBE), "transcribe",
            "--engine", "whisper",
            "--audio", str(wav),
            "--json",
            "--out", str(note_path),
            "--out-transcript", str(tr_path),
        ]
    )
    return json.loads(tr_path.read_text())


def quire(transcript: dict, tag: str) -> dict:
    req = llm_request(transcript)
    proc = subprocess.run(
        [str(LLM), "--model", str(QUIRE)],
        input=json.dumps(req).encode(),
        capture_output=True,
        timeout=180,
    )
    if proc.returncode != 0:
        err = proc.stderr.decode()[-400:]
        print("QUIRE FAIL", err)
        return {}
    payload = json.loads(proc.stdout.decode())
    (OUT / f"{tag}-quire.json").write_text(json.dumps(payload, indent=2))
    if not payload.get("ok"):
        print("QUIRE", payload.get("error"))
        return {}
    return payload.get("note") or {}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if not SCRIBE.exists() or not LLM.exists():
        print("building release bins…")
        subprocess.check_call(["cargo", "build", "--release", "-p", "scribe-cli", "-p", "scribe-llm"], cwd=ROOT)
    gold = json.loads(GOLD.read_text())

    print("\n== 1. mock ASR (sanity) ==")
    run([str(SCRIBE), "transcribe", "--engine", "mock", "--audio", str(OUT / "placeholder.wav")]) if False else None
    # mock needs a wav; generate 1s silence
    silence = OUT / "silence.wav"
    run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono", "-t", "1", str(silence)], capture_output=True)
    mock = subprocess.run(
        [str(SCRIBE), "transcribe", "--engine", "mock", "--audio", str(silence), "--json", "--out", str(OUT / "mock-note.json")],
        capture_output=True, text=True,
    )
    print(mock.stderr.strip()[-400:])

    print("\n== 2. TTS GP consult (one voice) ==")
    gp = OUT / "gp-consult.wav"
    say_wav(TRANSCRIPT.read_text().replace("CLINICIAN:", "Doctor:").replace("PATIENT:", "Patient:"), gp, "Daniel")
    print("duration", subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(gp)], text=True).strip(), "s")
    tr = transcribe(gp, "gp")
    print("segments", len(tr.get("segments") or []), "engine", tr.get("engine"))
    note = quire(tr, "gp")
    if note:
        print("QUIRE", json.dumps(score(note, gold)))

    print("\n== 3. Two-voice TTS (diarisation) ==")
    duo = OUT / "gp-two-voice.wav"
    two_voice_consult(duo)
    tr2 = transcribe(duo, "duo")
    speakers = {s.get("speaker") for s in tr2.get("segments") or []}
    print("segments", len(tr2.get("segments") or []), "speakers", speakers)
    note2 = quire(tr2, "duo")
    if note2:
        print("QUIRE", json.dumps(score(note2, gold)))

    print("\n== 4. Public two-speaker tape (archive.org) ==")
    src = OUT / "beatles.mp3"
    if not src.exists():
        try:
            run(["curl", "-fsSL", "--max-time", "60", "-o", str(src), BEATLES])
        except subprocess.CalledProcessError:
            print("skip: archive.org download failed")
            src = None
    if src and src.exists() and src.stat().st_size > 1000:
        wav = OUT / "beatles.wav"
        run(["ffmpeg", "-y", "-i", str(src), "-t", "45", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(wav)], capture_output=True)
        tr3 = transcribe(wav, "beatles")
        speakers = {s.get("speaker") for s in tr3.get("segments") or []}
        print("segments", len(tr3.get("segments") or []), "speakers", speakers)
        print("first lines:")
        for seg in (tr3.get("segments") or [])[:4]:
            print(" ", seg.get("speaker"), (seg.get("text") or "")[:80])

    print("\nArtifacts in", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
