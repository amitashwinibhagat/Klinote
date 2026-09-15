# Speech recognition

There are two paths, and they are deliberately different.

**The macOS app recognises with Apple's `SpeechAnalyzer`**, in Swift, in
`apps/Klinote/Sources/Core/Transcriber.swift`. The words then cross the FFI as
timed segments and the Rust core files them (`ScribePipeline::process_segments`).

**The Rust engine keeps an `AsrEngine` trait**, and `scribe-cli` still ships
whisper.cpp behind it. `MockAsrEngine` remains the default for tests and CI, so
`cargo test --workspace` stays model-free.

The reason the app does not use whisper.cpp any more: it cost a 465 MB download
before a clinician could record anything, it put a large C++ model parser in an
app that holds clinical records, and `SpeechAnalyzer` is already on the Mac and
runs an 80-second consultation in about a second. What whisper.cpp gave us that
this does not is speaker-boundary detection; `TurnTakingDiarizer` in the core
takes that over, from the gaps between segments, and the margin still offers
Swap.

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
| **Apple `SpeechAnalyzer`** | Swift | **macOS 26+** | **Shipped in the app.** Streaming, on-device, no model download, ~1 s for an 80 s consult. | No speaker labels: `TurnTakingDiarizer` guesses turns from gaps, and the margin has to offer Swap. |
| **whisper.cpp + tinydiarize SBD** (`scribe-asr-whisper`) | Rust | any macOS | **Shipped in `scribe-cli`.** Open-source, Metal-accelerated, two-speaker SBD. | 465 MB model; SBD is A/B not identity; role mapping is a clinician judgment. **No longer in the app** — nothing in `scribe-ffi` links it. |
| **sherpa-onnx** (`sherpa-rs`) | Rust | any macOS | Streaming, small models, has diarisation and VAD models in the same runtime. | More integration work; ONNX Runtime dependency. |
| **Parakeet TDT** | Rust/ONNX | any macOS | Very fast, small, strong English accuracy. | Needs ONNX runtime; fewer languages. |
| **Cloud** | — | — | — | **Never.** Violates the product's only real promise. |

**Shipped:** `SpeechAnalyzer` + `SpeechTranscriber` in the app; whisper.cpp in
`scribe-cli` only. Verified on 2026-09-15 (macOS 26.6.2, Xcode 26.6, M4) — the
app bundle contains no whisper symbols and `cargo tree -p scribe-ffi` has no
speech or llama dependency at all.

**This file used to say `SpeechAnalyzer` was not in the SDK.** The claim that it
was "not in the macOS 26.5 SDK this build targets" was wrong, and it was
load-bearing: it made the 465 MB first-use download look unavoidable. Checked
against the installed SDK rather than remembered:

```
$ grep -B2 "actor SpeechAnalyzer" \
    "$(xcrun --show-sdk-path)/System/Library/Frameworks/Speech.framework/\
Versions/A/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface"
@available(macOS 26.0, iOS 26.0, visionOS 26.0, tvOS 26.0, *)
@available(watchOS, unavailable)
final public actor SpeechAnalyzer : Swift.Sendable
```

`SpeechTranscriber`, `SpeechDetector`, `DictationTranscriber`, `AssetInventory`
and `ContextualStringsTag` are all `@available(macOS 26.0, *)` in that file.

### One API trap, measured

`SpeechAnalyzer` has both an `init(inputAudioFile:…)` and an
`analyzeSequence(from:)`, and they sit side by side in the framework headers.
Calling the second after the first **starts the same file twice**: the process
dies with `SIGTRAP` inside the framework before a single result arrives. Use the
file initialiser and await `transcriber.results`; that is the whole call. See the
comment in `Transcriber.swift`.

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

**`SpeechAnalyzer` made this harder.** whisper.cpp's tinydiarize gave
speaker-boundary detection from the acoustics. `SpeechTranscriber` gives none,
and it reports **contiguous** ranges — one result ends exactly where the next
begins — so the silence between turns is not in the segment timings at all. There
is nothing in the transcript to alternate on, and measuring the gaps instead
scored **52%** role accuracy on the two-voice bench, with 5 speaker changes found
where the consultation had 17. A coin flip, on the field `ASR.md` already calls
the most common failure mode of every ambient scribe.

So the two voices are separated by how they *sound*, in
`crates/scribe-diarize/src/acoustic.rs` — `AcousticDiarizer`:

- two features per utterance, median **fundamental frequency** (autocorrelation)
  and **zero-crossing rate**, no model and no download;
- deterministic 2-means over log-pitch, fixed initialisation, no random restart;
- a **`MIN_PITCH_SEPARATION` guard** (≈15%, about two semitones): if the two
  clusters are closer than that, it reports **one speaker** rather than inventing
  a second out of one person's ordinary variation. That guard is what keeps a
  dictated note from alternating roles arbitrarily.
- It diarises the **ASR segments**, not the VAD's spans. The VAD merges
  everything between two silences into one span, so two people talking back to
  back — most of a consultation — arrive as a single span with a single voice and
  nothing left to separate. It found 7 spans for 18 turns.
- With no audio it falls back to `TurnTakingDiarizer`'s gaps, which is worse and
  is meant to be.

### Measured, `scripts/diarize-bench.py`

Two-voice synthesis of the sample consultation, scored against the turns the
script actually spoke:

| Scenario | Speakers found | Role accuracy |
|---|---|---|
| Before: gaps only (baseline) | 2 | **0.52** (13/25) |
| Two voices, male + female | 2 | **1.00** (25/25) |
| One voice (dictation) | 1 ✅ | — (no real turns) |
| **Two male voices, close pitch** | **1 ❌** | 0.79 (19/24) |

**The last row is the honest limit, and it is not a pass.** Two voices of the
same sex are not separated: the guard fires, and it reports one speaker. That is
the *safe* failure — it does not invent a turn nobody made — but it means role
attribution is inert for a same-sex pair, and every utterance is filed as the
clinician. About half of two-person consultations will be like this.

### Why pitch cannot fix it, in one table

The diariser prints the log-pitch distance it measured, which is the number the
guard tests. Instrumenting it once, over the three bench scenarios:

| Scenario | log-pitch distance | Guard | Outcome |
|---|---|---|---|
| Male + female | **0.4386** | 0.14 | split, correctly |
| One voice (dictation) | **0.0909** | 0.14 | not split, correctly |
| **Two male voices** | **0.1017** | 0.14 | not split — **wrong, there are two** |

The two men differ by 0.1017. One man's ordinary variation across a consultation
is 0.0909. **The signal and the noise are the same size**, so no threshold can
divide them: any guard low enough to catch the two men also splits a solo
dictation, and inventing speaker changes in a one-person note is worse than
leaving two voices joined. This is not a tuning problem to come back to.

### A timbre-based attempt, and why it was reverted

Since pitch is exhausted, the second, independent feature is timbre — the shape of
the spectral envelope, which two people can differ in while holding the same note.
A mel-filterbank cepstral extractor (`spectral.rs`) was written for it, with no
dependency: windowed DFT, 24 mel bands, log, DCT-II, 12 coefficients per utterance,
then k-means over the standardised vectors with a silhouette guard.

On the bench it was **worse, and reverted**: all three scenarios reported one
speaker, including the male/female pair that pitch gets at 100%. Segment-length
cepstra did not separate the voices, and the silhouette guard then rejected every
split. Lowering the threshold until the bench passed would have been fitting a
number to synthetic TTS, which is the mistake this file keeps warning about. The
module was deleted rather than left wired to nothing.

It is written down because the negative result is the useful part: **more DSP is
not the way out.** What was tried is in this section, so it does not need to be
tried again.

The real fix is speaker **embeddings** — the upgrade path is pyannote
segmentation + embeddings over ONNX, behind the existing `Diarizer` trait. That
means a model, which means reviewing the download decision in `ADR/0002` and
`LLM-BENCH.md`, so it is a product choice rather than a refactor. Until then the
shell **must** keep offering one-click role correction ("this was the patient"),
because the heuristic will be wrong in noisy rooms and for similar voices, and a
wrong role is worse than an unfiled sentence. Treat same-sex separation as an
open, well-characterised problem, not as solved.

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
