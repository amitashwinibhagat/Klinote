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
pub use scribe_asr::AsrOptions;
pub use scribe_audio::AudioBuffer as Audio;
use scribe_core::{
    ClinicalNote, Discipline, Encounter, EncounterId, Result, Speaker, SpeakerId, SpeakerRole,
    Transcript, parse_transcript_text,
};
use scribe_diarize::{Diarization, Diarizer, TurnTakingDiarizer};
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
            templates: TemplateLibrary::builtin()?,
            asr: Box::new(MockAsrEngine),
            diarizer: Box::new(TurnTakingDiarizer::default()),
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

        let transcript = self.assemble_transcript(
            encounter.id,
            &asr_output.segments,
            &diarization,
            &asr_output.language,
            &asr_output.engine,
        );

        let note = self.generate(encounter, &transcript)?;

        Ok(PipelineOutput {
            transcript,
            note,
            speech_spans,
        })
    }

    /// Human transcript in, note out. No model, no audio.
    pub fn process_text(&self, encounter: &Encounter, text: &str) -> Result<PipelineOutput> {
        let transcript = parse_transcript_text(text, encounter.id, "en")?;
        let note = self.generate(encounter, &transcript)?;
        Ok(PipelineOutput {
            transcript,
            note,
            speech_spans: Vec::new(),
        })
    }

    fn generate(&self, encounter: &Encounter, transcript: &Transcript) -> Result<ClinicalNote> {
        let template = self.templates.get(encounter.template_id.as_str())?;
        self.generator.generate(&GenerationRequest {
            encounter,
            transcript,
            template,
        })
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
