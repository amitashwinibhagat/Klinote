# Note-model bench

Same SOAP job, several local GGUFs. The question is not “which model is SOTA”
— it is which one can extract a GP consult into SOAP **without inventing facts
or filing the parking line**.

## Job

`fixtures/sample-transcript.txt` → SOAP with evidence citations.

Must include: sore throat, four days, swallow, tired, cetirizine, 37.4,
erythema, viral, paracetamol, ibuprofen, one week.

Must **not** include: parking (deliberately unclinical; belongs in unfiled).

## Catalog

See `fixtures/note-bench/catalog.json`.

**sub-1gb** — MiniCPM5-1B Q4, Llama 3.2 1B Q4, Gemma 3 1B Q4, Qwen2.5-1.5B Q4, Qwen3-0.6B Q8.

**1-2gb** — MiniCPM5-2B Q4 (1.56), Qwen3-1.7B Q8 (1.83), Qwen2.5-3B Q4 (1.93), Gemma 3 4B IQ3 (1.99), Llama 3.2 3B Q4 (2.02).

## Run

```bash
# Build the drafter once
cargo build --release -p scribe-llm

# Score whatever GGUFs are already in Application Support
python3 scripts/note-bench.py

# Fetch / score a size band
python3 scripts/note-bench.py --band sub-1gb --download
python3 scripts/note-bench.py --band 1-2gb --download

# One model
python3 scripts/note-bench.py --only minicpm5-2b-q4
```

Models land in `~/Library/Application Support/Nota/Models/` — same folder the
app uses. Per-model JSON (note + score) is written beside them as
`bench-<id>.json`. The last table is `fixtures/note-bench/last-report.json`.

## How to read the table

| Column | Want |
|---|---|
| sec | Lower. First load is slow; ignore absolute times on first run. |
| req | `4/4` SOAP required sections filled. |
| ev | Evidence precision: cited segment ids that exist. `1.00` is the contract. |
| gold | Fraction of must-appear facts found in the note body. |
| leak | `no` — “parking” must not enter SOAP. |
| unfiled | Parking (and small talk) should live here, not zero at the cost of a leak. |

A model that files parking into Plan **fails** even if gold recall is high.

## Not in CI

This needs GGUFs and Metal. `cargo test` stays model-free.
