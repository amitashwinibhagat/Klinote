# Note engine

Production model: **Qwen3-4B Instruct 2507 Q3_K_S** (1.89 GB).

Downloaded once by Settings into
`~/Library/Application Support/Nota/Models/quire.gguf`.
The app calls it Quire. Do not surface the upstream model name in UI.
The Swift shell never talks to the network except for that download. `scribe-llm`
reads the GGUF and writes a SOAP JSON with evidence indices.

## Regression

```bash
cargo build --release -p scribe-llm
python3 scripts/note-bench.py --only quire
```

Want: `4/4` required sections, evidence `1.00`, parking leak `no`.
Gold recall is literal (`four days` vs `4 days`) — read the note, not just the score.

Not in CI. Needs the GGUF and Metal.
