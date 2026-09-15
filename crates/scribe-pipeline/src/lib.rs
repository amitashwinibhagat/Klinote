//! The single orchestration point of the engine.
//!
//! Callers (CLI, FFI, tests) should not assemble ASR + diarisation + note
//! generation by hand; they construct a [`ScribePipeline`] and call
//! [`ScribePipeline::process_audio`] or [`ScribePipeline::process_text`].
//!
//! Everything this crate does is local. There is no network code anywhere in
//! the workspace, and the pipeline trait objects cannot introduce one without
//! an explicit, reviewable change here.

use scribe_asr::{AsrEngine, MockAsrEngine};
use scribe_audio::{AudioBuffer, SpeechSpan, VadConfig, detect_speech};

/// Re-exported so callers (CLI, FFI, Swift) do not need to depend on the
/// individual engine crates.
pub use scribe_asr::{AsrOptions, AsrSegment};
pub use scribe_audio::AudioBuffer as Audio;
use scribe_core::{
    ClinicalNote, Discipline, Encounter, EncounterId, Result, Speaker, SpeakerId, SpeakerRole,
    Transcript, parse_transcript_text,
};
use scribe_diarize::{AcousticDiarizer, Diarization, Diarizer};
use scribe_note::{GenerationRequest, NoteGenerator, RuleBasedGenerator, TemplateLibrary};

/// Which diarisation speaker maps to which clinical role.
///
/// The shell owns the UI that lets a clinician correct this; the engine only
/// needs a sane default.
#[derive(Debug, Clone, Copy)]
pub struct RoleMap {
    pub speaker_zero: SpeakerRole,
    pub speaker_one: SpeakerRole,
}

impl Default for RoleMap {
    fn default() -> Self {
        Self {
            speaker_zero: SpeakerRole::Clinician,
            speaker_one: SpeakerRole::Patient,
        }
    }
}

impl RoleMap {
    pub fn role_for(&self, speaker: SpeakerId) -> SpeakerRole {
        match speaker.0 {
            0 => self.speaker_zero,
            1 => self.speaker_one,
            _ => SpeakerRole::Other,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PipelineOutput {
    pub transcript: Transcript,
    pub note: ClinicalNote,
    pub speech_spans: Vec<SpeechSpan>,
}

pub struct ScribePipeline {
    templates: TemplateLibrary,
    asr: Box<dyn AsrEngine + Send + Sync>,
    diarizer: Box<dyn Diarizer + Send + Sync>,
    generator: Box<dyn NoteGenerator + Send + Sync>,
    role_map: RoleMap,
    vad: VadConfig,
    /// ASR engines work best at 16 kHz; the shell should capture at whatever
    /// the hardware likes and let us resample.
    asr_sample_rate: u32,
}

impl ScribePipeline {
    /// Default engine: rule-based notes, turn-taking diarisation, mock ASR.
    ///
    /// The mock ASR is a deliberate default for the concierge phase — it lets
    /// the whole product run without a model download. Swap it with
    /// [`ScribePipeline::with_asr`] to go live.
    pub fn new() -> Result<Self> {
        Ok(Self {
            templates: TemplateLibrary::for_this_machine()?,
            asr: Box::new(MockAsrEngine),
            // Acoustic, not turn-taking. With a real recording the diarizer is
            // given the waveform and separates the two voices by pitch; the
            // silence heuristic is only its fallback when there is no audio.
            diarizer: Box::new(AcousticDiarizer::default()),
            generator: Box::new(RuleBasedGenerator),
            role_map: RoleMap::default(),
            vad: VadConfig::default(),
            asr_sample_rate: 16_000,
        })
    }

    pub fn with_asr(mut self, asr: Box<dyn AsrEngine + Send + Sync>) -> Self {
        self.asr = asr;
        self
    }

    pub fn with_diarizer(mut self, diarizer: Box<dyn Diarizer + Send + Sync>) -> Self {
        self.diarizer = diarizer;
        self
    }

    pub fn with_generator(mut self, generator: Box<dyn NoteGenerator + Send + Sync>) -> Self {
        self.generator = generator;
        self
    }

    pub fn with_role_map(mut self, role_map: RoleMap) -> Self {
        self.role_map = role_map;
        self
    }

    pub fn with_vad(mut self, vad: VadConfig) -> Self {
        self.vad = vad;
        self
    }

    pub fn with_templates(mut self, templates: TemplateLibrary) -> Self {
        self.templates = templates;
        self
    }

    pub fn templates(&self) -> &TemplateLibrary {
        &self.templates
    }

    pub fn asr_engine_name(&self) -> &str {
        self.asr.name()
    }

    /// Audio in, note out.
    pub fn process_audio(
        &self,
        encounter: &Encounter,
        audio: &AudioBuffer,
        options: &AsrOptions,
    ) -> Result<PipelineOutput> {
        let prepared = audio.resample_to(self.asr_sample_rate);
        let speech_spans = detect_speech(&prepared, self.vad);
        let asr_output = self.asr.transcribe(&prepared, &speech_spans, options)?;
        let diarization = self.diarizer.diarize(&prepared, &speech_spans)?;

        let mut transcript = self.assemble_transcript(
            encounter.id,
            &asr_output.segments,
            &diarization,
            &asr_output.language,
            &asr_output.engine,
        );
        transcript.name_checks = scribe_core::suggest_names(&transcript);

        let note = self.generate(encounter, &transcript)?;

        Ok(PipelineOutput {
            transcript,
            note,
            speech_spans,
        })
    }

    /// Recognised words in, note out. No audio, no ASR engine.
    ///
    /// Recognition is the shell's job on macOS: `SpeechAnalyzer` is a Swift API
    /// and cannot be called from Rust. What the pipeline still owns is
    /// everything *after* the words — diarisation, role mapping, the grounding
    /// check, completeness — so the shell recognises, hands over timed
    /// segments, and gets back the same [`PipelineOutput`] the audio path
    /// produces. Do not let a caller assemble those stages itself.
    ///
    /// `audio` is where the two speakers come from, and it is not optional in
    /// practice. `SpeechTranscriber` reports **contiguous** ranges — one result
    /// ends exactly where the next begins — so the silence between turns is not
    /// present in the segment timings, and the spaces it finds are usually the
    /// same length whether or not the speaker changed. Hand over the recording
    /// and the pipeline runs the VAD and hands the spans to the diarizer, which
    /// is why this takes an `AudioBuffer` rather than a ready-made span list:
    /// an acoustic diarizer needs the waveform, not just the timings.
    ///
    /// Without audio the pipeline still answers, from the segment timings. That
    /// is a real step down — one speaker, or arbitrary alternation — and it
    /// exists for the CLI and the tests, not for the app.
    pub fn process_segments(
        &self,
        encounter: &Encounter,
        segments: &[AsrSegment],
        audio: Option<&AudioBuffer>,
        language: &str,
        engine: &str,
    ) -> Result<PipelineOutput> {
        let from_segments: Vec<SpeechSpan> = segments
            .iter()
            .map(|segment| SpeechSpan {
                start_ms: segment.start_ms,
                end_ms: segment.end_ms,
            })
            .collect();

        let (spans, diarization) = match audio {
            Some(audio) => {
                // Diarise the *segments*, not the VAD's spans.
                //
                // The VAD's job is to find where speech is; it is not the right
                // unit for attribution. It merges everything between two
                // silences into one span, so two people talking back to back —
                // which is most of a consultation — arrive as a single span with
                // a single voice and nothing left to separate. On the two-voice
                // bench it found 7 spans for 18 turns.
                //
                // A segment is one utterance with its own audio, so measuring
                // pitch per segment gives one decision per utterance and lines
                // up exactly with what the evidence margin points at.
                let prepared = audio.resample_to(self.asr_sample_rate);
                let diarization = self.diarizer.diarize(&prepared, &from_segments)?;
                (from_segments, diarization)
            }
            None => {
                let diarization = self.diarizer.diarize_segments(&from_segments)?;
                (from_segments, diarization)
            }
        };

        let mut transcript =
            self.assemble_transcript(encounter.id, segments, &diarization, language, engine);
        transcript.name_checks = scribe_core::suggest_names(&transcript);

        let note = self.generate(encounter, &transcript)?;

        Ok(PipelineOutput {
            transcript,
            note,
            speech_spans: spans,
        })
    }

    /// Human transcript in, note out. No model, no audio.
    pub fn process_text(&self, encounter: &Encounter, text: &str) -> Result<PipelineOutput> {
        let mut transcript = parse_transcript_text(text, encounter.id, "en")?;
        transcript.name_checks = scribe_core::suggest_names(&transcript);
        let note = self.generate(encounter, &transcript)?;
        Ok(PipelineOutput {
            transcript,
            note,
            speech_spans: Vec::new(),
        })
    }

    /// Build a note from an already-assembled transcript.
    ///
    /// Public so the FFI stops hand-assembling a generator and silently skipping
    /// the grounding check: `scribe_note_from_transcript` called
    /// `RuleBasedGenerator` directly, so a note rebuilt from a stored transcript
    /// — after a speaker swap, say — never had `verify_support` run on it. Every
    /// path that produces a note goes through here.
    pub fn generate(&self, encounter: &Encounter, transcript: &Transcript) -> Result<ClinicalNote> {
        let template = self.templates.get(encounter.template_id.as_str())?;
        let mut note = self.generator.generate(&GenerationRequest {
            encounter,
            transcript,
            template,
        })?;
        // Grounding check on every path, rule-based included.
        note.verify_support(transcript);
        // A document the patient reads gets plain language, by expansion where
        // that is lossless and by flagging where it is not.
        if template.audience == scribe_core::Audience::Patient {
            note.simplify_for_patient();
        }
        Ok(note)
    }

    fn assemble_transcript(
        &self,
        encounter_id: EncounterId,
        segments: &[scribe_asr::AsrSegment],
        diarization: &Diarization,
        language: &str,
        engine: &str,
    ) -> Transcript {
        let mut transcript = Transcript::new(encounter_id, engine);
        transcript.language = language.to_owned();

        for asr_segment in segments {
            // Prefer the ASR backend's own speaker annotation (whisper.cpp
            // SBD) over silence-based diarisation when it is present.
            let speaker = asr_segment
                .speaker
                .or_else(|| diarization.speaker_at(asr_segment.start_ms))
                .unwrap_or(SpeakerId::CLINICIAN);
            let role = self.role_map.role_for(speaker);
            transcript.push_speaker(Speaker::new(speaker, role));

            let mut segment = scribe_core::Segment::new(
                speaker,
                asr_segment.start_ms,
                asr_segment.end_ms,
                asr_segment.text.clone(),
            );
            segment.confidence = asr_segment.confidence;
            transcript.push_segment(segment);
        }

        transcript
    }
}

impl Default for ScribePipeline {
    fn default() -> Self {
        Self::new().expect("built-in templates and default engines must construct")
    }
}

/// Convenience for callers that only need the default discipline mapping.
pub fn default_template_for(discipline: &Discipline) -> String {
    discipline.default_template().as_str().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use scribe_audio::AudioBuffer;

    fn tone(freq: f32, ms: u64, rate: u32) -> Vec<f32> {
        let count = (rate as u64 * ms / 1000) as usize;
        (0..count)
            .map(|i| {
                let t = i as f32 / rate as f32;
                (2.0 * std::f32::consts::PI * freq * t).sin() * 0.4
            })
            .collect()
    }

    #[test]
    fn text_pipeline_produces_a_soap_note() {
        let pipeline = ScribePipeline::new().unwrap();
        let encounter = Encounter::new("p-1", Discipline::GeneralPractice);

        let output = pipeline
            .process_text(
                &encounter,
                "CLINICIAN: On examination the throat shows erythema.\n\
                 CLINICIAN: Plan: rest and fluids, follow up in one week.",
            )
            .unwrap();

        assert_eq!(output.transcript.engine, "human-transcript");
        assert!(!output.note.section("objective").unwrap().is_empty());
        assert!(!output.note.section("plan").unwrap().is_empty());
        assert_eq!(output.note.template_id.as_str(), "soap");
    }

    #[test]
    fn audio_pipeline_runs_end_to_end_without_a_model() {
        let pipeline = ScribePipeline::new().unwrap();
        let encounter = Encounter::new("p-2", Discipline::GeneralPractice);

        let rate = 48_000;
        let mut samples = vec![0.0f32; rate as usize / 2];
        samples.extend(tone(200.0, 900, rate));
        samples.extend(vec![0.0f32; rate as usize / 2]);
        samples.extend(tone(240.0, 900, rate));
        samples.extend(vec![0.0f32; rate as usize]);
        let audio = AudioBuffer::new(samples, rate);

        let output = pipeline
            .process_audio(&encounter, &audio, &AsrOptions::default())
            .unwrap();

        assert_eq!(output.speech_spans.len(), 2, "{:?}", output.speech_spans);
        assert_eq!(output.transcript.segments.len(), 2);
        assert_eq!(output.transcript.engine, "mock");
        assert_eq!(output.note.engine, "rule-based-v1");
        // Two speakers were inferred from the silence gap.
        assert_eq!(output.transcript.speakers.len(), 2);
    }

    /// The shell recognises, the pipeline files. This is the path the macOS app
    /// takes now: `SpeechAnalyzer` produces the words, and there is no audio on
    /// this side of the boundary.
    #[test]
    fn segments_pipeline_diarises_from_timings_alone() {
        let pipeline = ScribePipeline::new().unwrap();
        let encounter = Encounter::new("p-4", Discipline::GeneralPractice);

        // ~1 s of silence between each turn, which is what TurnTakingDiarizer
        // reads. The clinician asks, the patient answers, the clinician
        // examines and plans.
        let segments = vec![
            AsrSegment::new(0, 4000, "Good morning, what brings you in today?"),
            AsrSegment::new(5000, 9000, "I have had a sore throat for four days."),
            AsrSegment::new(10_000, 14_000, "On examination the throat shows erythema."),
            AsrSegment::new(
                15_000,
                19_000,
                "Plan: rest and fluids, follow up in one week.",
            ),
        ];

        let output = pipeline
            .process_segments(&encounter, &segments, None, "en", "apple-speechanalyzer")
            .unwrap();

        assert_eq!(output.transcript.engine, "apple-speechanalyzer");
        assert_eq!(output.transcript.segments.len(), 4);
        assert_eq!(output.transcript.speakers.len(), 2);
        assert_eq!(output.speech_spans.len(), 4);

        // The clinician's examination and plan must land in their sections,
        // which also proves the roles were assigned the right way round.
        assert!(!output.note.section("objective").unwrap().is_empty());
        assert!(!output.note.section("plan").unwrap().is_empty());
    }

    /// The regression the acoustic diarizer exists for.
    ///
    /// `SpeechTranscriber` reports contiguous ranges — each segment starts where
    /// the last ended — and the pauses it leaves are the same length whether or
    /// not the speaker changed. So two voices have to be told apart by how they
    /// *sound*. Here the segments butt against each other with a 1.5 s gap in
    /// the middle that a gap-based heuristic cannot use, because the gap is not
    /// where the speaker changed.
    #[test]
    fn two_voices_are_separated_by_pitch_not_by_gaps() {
        let pipeline = ScribePipeline::new().unwrap();
        let encounter = Encounter::new("p-5", Discipline::GeneralPractice);

        // A low voice, then a high one. Sample rate 16 kHz because that is what
        // the pipeline resamples to.
        let rate = 16_000;
        let mut samples = tone(110.0, 3000, rate);
        samples.extend(tone(230.0, 3000, rate));
        let audio = AudioBuffer::new(samples, rate);

        // Contiguous, exactly as the recogniser reports them.
        let segments = vec![
            AsrSegment::new(0, 3000, "On examination the throat shows erythema."),
            AsrSegment::new(3000, 6000, "I have had a sore throat for four days."),
        ];

        // Without the recording there is nothing to hear, and the honest answer
        // is one speaker — not an invented turn.
        let without = pipeline
            .process_segments(&encounter, &segments, None, "en", "shell")
            .unwrap();
        assert_eq!(
            without.transcript.speakers.len(),
            1,
            "contiguous ranges cannot show a turn change — this is the bug"
        );

        let with = pipeline
            .process_segments(&encounter, &segments, Some(&audio), "en", "shell")
            .unwrap();
        assert_eq!(with.transcript.speakers.len(), 2);
        // And the roles come out the right way round: the clinician examines,
        // the patient reports the symptom.
        assert_eq!(with.transcript.segments[0].speaker, SpeakerId::new(0));
        assert_eq!(with.transcript.segments[1].speaker, SpeakerId::new(1));
        assert_eq!(with.transcript.speakers[0].role, SpeakerRole::Clinician);
        assert_eq!(with.transcript.speakers[1].role, SpeakerRole::Patient);
    }

    #[test]
    fn unknown_template_is_reported_not_guessed() {
        let pipeline = ScribePipeline::new().unwrap();
        let mut encounter = Encounter::new("p-3", Discipline::GeneralPractice);
        encounter.template_id = scribe_core::TemplateId::new("does-not-exist");

        let err = pipeline
            .process_text(&encounter, "CLINICIAN: hello there")
            .unwrap_err();
        assert!(matches!(err, scribe_core::ScribeError::TemplateNotFound(_)));
    }
}
