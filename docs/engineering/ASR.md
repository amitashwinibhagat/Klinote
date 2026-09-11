# Speech recognition

The engine abstracts ASR behind `scribe_asr::AsrEngine`. v0 ships only
`MockAsrEngine`; this document is the plan for going live.

```rust
pub trait AsrEngine {
    fn name(&self) -> &str;
    fn transcribe(&self, audio: &AudioBuffer, spans: &[SpeechSpan], options: &AsrOptions)
        -> Result<AsrOutput>;
}
```

## Choosing an engine

| Backend | Language | Where | Why | Why not |
|---|---|---|---|---|
| **Apple `SpeechAnalyzer`** | Swift | macOS 26+ | Free, streaming, on-device, no model download, no notarisation constraint, Apple-tuned for dictation. Best default. | Swift-only API, so it lives in the shell; requires implementation of `AsrEngine` in Swift and crossing the FFI (or generating the note in Swift). |
| **whisper.cpp** (`whisper-rs`) | Rust | any macOS | Portable, well understood, large model zoo, word timestamps. | Larger binary/weights, slower than Parakeet, needs a bundled or downloaded model. |
| **sherpa-onnx** (`sherpa-rs`) | Rust | any macOS | Streaming, small models, has diarisation and VAD models in the same runtime. | More integration work; ONNX Runtime dependency. |
| **Parakeet TDT** | Rust/ONNX | any macOS | Very fast, small, strong English accuracy. | Needs ONNX runtime; fewer languages. |
| **Cloud** | — | — | — | **Never.** Violates the product's only real promise. |

**Recommendation:** `SpeechAnalyzer` in the Swift shell for the macOS-first
product; keep `AsrEngine` implemented for a Rust fallback so the engine stays
useful for batch processing, Windows later, and tests.

## Implementation notes, whichever backend

- **Resample to 16 kHz mono first.** `AudioBuffer::resample_to(16_000)` does
  this; ASR models are trained at 16 kHz and feeding 48 kHz is a silent quality
  loss.
- **Use the VAD spans.** `detect_speech` already removes silence. Passing spans
  to the engine cuts inference time proportionally and stops hallucination on
  silence, which is a real failure mode of Whisper-class models.
- **Stream, don't batch, in the app.** A 20-minute consult should not take 20
  minutes to appear. `SpeechAnalyzer` is built for this.
- **Keep `confidence`.** It is already in `AsrSegment` and `Segment`. Low
  confidence is a useful flag for the reviewer and for routing decisions.
- **Do not let the ASR engine decide roles.** It returns text and timing;
  diarisation and `RoleMap` assign roles.

## Medical vocabulary

Generic models mis-hear clinical terms — drug names, anatomy, abbreviations.
Three levers, in order of cost:

1. **Apple's `SpeechTranscriber` contextual hints** / Whisper `initial_prompt`
   with a per-discipline term list. Cheap and effective.
2. **A post-ASR correction pass** against a practice vocabulary list. Belongs
   in the pipeline as a stage, not inside the ASR engine.
3. **Fine-tuning.** Expensive, and only worth it once the concierge data shows
   which terms actually fail.

Do not start with (3).

## Diarisation

`TurnTakingDiarizer` is a two-speaker heuristic: it alternates on silence gaps.
It is honest about being a heuristic, and role assignment is the most common
failure mode of every ambient scribe.

The upgrade path is pyannote segmentation + speaker embeddings over ONNX, behind
the existing `Diarizer` trait. Until then the shell **must** offer one-click
role correction ("this was the patient"), because the model will be wrong in
noisy exam rooms and a wrong role is worse than an unfiled sentence.

## Adding an engine

```rust
struct MyEngine { /* ... */ }

impl AsrEngine for MyEngine {
    fn name(&self) -> &str { "my-engine-v1" }

    fn transcribe(
        &self,
        audio: &AudioBuffer,
        spans: &[SpeechSpan],
        options: &AsrOptions,
    ) -> Result<AsrOutput> {
        // Must not perform network I/O. Ever.
        todo!()
    }
}

let pipeline = ScribePipeline::new()?.with_asr(Box::new(MyEngine { /* ... */ }));
```

Do not modify `ScribePipeline` to add an engine. If the trait does not fit,
change the trait — deliberately, with an ADR.

## Testing an ASR engine

- Model-dependent tests get a Cargo feature and are **off by default**, so
  `cargo test --workspace` stays model-free and CI stays fast.
- Fixture audio must be synthetic (generated tones or public-domain speech),
  never a real consultation recording.
- Measure and record word error rate on a fixed synthetic set so regressions
  are visible.
