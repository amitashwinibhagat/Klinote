# Speech recognition

The engine abstracts ASR behind `scribe_asr::AsrEngine`. The shipped live
backend is **whisper.cpp with tinydiarize SBD** (`scribe-asr-whisper`), loaded
from a GGUF the Swift shell downloads on first use. `MockAsrEngine` remains
the default for tests and CI.

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
| **whisper.cpp + tinydiarize SBD** (`scribe-asr-whisper`) | Rust | any macOS | **Shipped.** Open-source, Metal-accelerated, two-speaker SBD, first-use download. | 465 MB model; SBD is A/B not identity; role mapping is a clinician judgment. |
| **Apple `SpeechAnalyzer`** | Swift | macOS 27+ | Free, streaming, on-device, no model download. | Not in the macOS 26.5 SDK this build targets. Upgrade path when Golden Gate ships. |
| **sherpa-onnx** (`sherpa-rs`) | Rust | any macOS | Streaming, small models, has diarisation and VAD models in the same runtime. | More integration work; ONNX Runtime dependency. |
| **Parakeet TDT** | Rust/ONNX | any macOS | Very fast, small, strong English accuracy. | Needs ONNX runtime; fewer languages. |
| **Cloud** | — | — | — | **Never.** Violates the product's only real promise. |

**Shipped:** whisper.cpp (`ggml-small.en-tdrz.bin`) in the Rust core, downloaded
once by the Swift shell into `~/Library/Application Support/Klinote/Models/`.
`SpeechAnalyzer` remains the upgrade path when macOS 27's SDK lands.

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

## A discarded chunk is a silent failure

whisper.cpp throws away the rest of a 30-second chunk when a segment ends on a
lone trailing timestamp token — `single timestamp ending - skip entire chunk`,
whisper.cpp §2629. The model emits that token when it decides the audio has
ended, and it decides that prematurely after a short opening turn. A
fifteen-second consult can come back with only its first four seconds
transcribed.

Nothing downstream can tell. The transcript is short but well formed, the note
that follows is thin but plausible, and the clinician has no reason to suspect
that most of the consultation was dropped. Measured on a two-turn clip:

| clip | before | after |
| --- | --- | --- |
| greeting then patient, 13.5 s | 67 chars | 246 |
| three turns, 22.9 s | 67 | 426 |
| 32.4 s | 114 | 660 |
| 51.3 s | 81 | 1,027 |

Two repairs, both in `scribe-asr-whisper`, both only when the result looks
wrong so an ordinary recording still costs one pass:

1. **The transcript stops short of the audio.** Transcribe the uncovered tail
   again and splice it, continuing the clock. The audio after a discarded chunk
   begins where the decoder thought a turn had ended, so the tail starts on the
   other voice — otherwise the patient's only words merge into the clinician's
   greeting.
2. **The transcript claims to cover the audio but holds almost no text**,
   because the end timestamp was stretched over the discarded span. Density is
   the only signal left, so an implausibly sparse recording is halved and each
   half transcribed on its own; a window starting mid-speech does not see the
   end of a turn and does not give up. Kept only if it finds at least double the
   text and at least 40 characters, and only for recordings under two minutes,
   so the extra work stays bounded.

A recovered voice label is still a guess. The margin offers Swap for exactly
that.

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
