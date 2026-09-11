# Note-model bench

Same SOAP job, several small GGUFs. The question is not “which model is SOTA”
— it is which one under ~1 GB can extract a GP consult into SOAP **without
inventing facts or filing the parking line**.

## Job

`fixtures/sample-transcript.txt` → SOAP with evidence citations.

Must include: sore throat, four days, swallow, tired, cetirizine, 37.4,
erythema, viral, paracetamol, ibuprofen, one week.

Must **not** include: parking (deliberately unclinical; belongs in unfiled).

## Catalog (all under 1 GB)

See `fixtures/note-bench/catalog.json`.

| id | Model | Size |
|---|---|---|
| minicpm5-1b-q4 | MiniCPM5-1B Q4_K_M | 0.69 GB |
| llama32-1b-q4 | Llama 3.2 1B Instruct Q4_K_M | 0.81 GB |
| gemma3-1b-q4 | Gemma 3 1B IT Q4_K_M | 0.81 GB |
| qwen25-1.5b-q4 | Qwen2.5-1.5B Instruct Q4_K_M | 0.99 GB |
| qwen3-0.6b-q8 | Qwen3-0.6B Q8_0 | 0.64 GB |

## Run

```bash
# Build the drafter once
cargo build --release -p scribe-llm

# Score whatever GGUFs are already in Application Support
python3 scripts/note-bench.py

# Fetch the whole catalog (still < 5 GB total)
python3 scripts/note-bench.py --download

# One model
python3 scripts/note-bench.py --only minicpm5-1b-q4
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
