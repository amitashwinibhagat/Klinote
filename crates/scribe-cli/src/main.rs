//! `scribe` — the engine's command-line driver.
//!
//! Two jobs:
//!
//! 1. **Run the pipeline** on a recording (`transcribe`) or a human transcript
//!    (`note`), and emit a draft note as Markdown or JSON.
//! 2. **Be the concierge tool** for the validation sprint: paste a real
//!    encounter transcript, get a structured note, email it. No app, no model,
//!    no account — which is exactly what the first ten clinics should see.

use std::io::Read;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Args, Parser, Subcommand};
use scribe_core::{Discipline, Encounter, Result, TemplateId};
use scribe_pipeline::ScribePipeline;
use scribe_store::Store;

#[derive(Parser, Debug)]
#[command(
    name = "scribe",
    version,
    about = "Local Clinical Scribe — on-device clinical documentation",
    long_about = "Turns a recording or a transcript into a structured clinical note. \
                  Runs entirely on this Mac: no network, no account, no model required for v0."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// List the note templates compiled into this build.
    Templates,

    /// Generate a note from a plain-text transcript (no audio, no model).
    Note(NoteArgs),

    /// Transcribe an audio file and generate a note from it.
    Transcribe(TranscribeArgs),

    /// Show the audit trail for a subject from a local database.
    Audit(AuditArgs),
}

#[derive(Args, Debug)]
struct CommonArgs {
    /// Template id, e.g. `soap`, `physiotherapy`, `psychology`, `dentistry`, `veterinary`.
    #[arg(long, default_value = "soap")]
    template: String,

    /// Opaque pseudonym for the patient. Never a name or an MRN.
    #[arg(long, default_value = "local-anonymous")]
    patient_ref: String,

    /// Clinician identifier (opaque).
    #[arg(long)]
    clinician: Option<String>,

    /// Discipline key, e.g. `general_practice`, `physiotherapy`, `veterinary`.
    #[arg(long, default_value = "general_practice")]
    discipline: String,

    /// Emit JSON instead of Markdown.
    #[arg(long)]
    json: bool,

    /// Write output here instead of stdout.
    #[arg(long)]
    out: Option<PathBuf>,

    /// Persist the encounter, transcript and note to this SQLite database.
    #[arg(long)]
    db: Option<PathBuf>,

    /// Write the transcript JSON here (whisper/mock segments + speakers).
    #[arg(long)]
    out_transcript: Option<PathBuf>,

    /// Actor recorded in the audit log.
    #[arg(long, default_value = "cli")]
    actor: String,
}

#[derive(Args, Debug)]
struct NoteArgs {
    /// Transcript file, or `-` for stdin.
    #[arg(long)]
    transcript: String,

    #[command(flatten)]
    common: CommonArgs,
}

#[derive(Args, Debug)]
struct TranscribeArgs {
    /// Audio file (WAV: 16-bit PCM, 32-bit PCM or 32-bit float).
    #[arg(long)]
    audio: PathBuf,

    /// ASR engine to use: `mock` (synthetic) or `whisper` (on-device whisper.cpp, requires the model).
    #[arg(long, default_value = "mock")]
    engine: String,

    #[command(flatten)]
    common: CommonArgs,
}

#[derive(Args, Debug)]
struct AuditArgs {
    #[arg(long)]
    db: PathBuf,

    /// Subject id to trace, e.g. a note id.
    #[arg(long)]
    subject: String,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Command::Templates => list_templates(),
        Command::Note(args) => run_note(args),
        Command::Transcribe(args) => run_transcribe(args),
        Command::Audit(args) => run_audit(args),
    }
}

fn list_templates() -> Result<()> {
    let pipeline = ScribePipeline::new()?;
    for template in pipeline.templates().iter() {
        println!(
            "{:<14} {} ({})",
            template.id.as_str(),
            template.name,
            template.discipline
        );
        if !template.description.is_empty() {
            println!("               {}", template.description);
        }
        for section in &template.sections {
            let marker = if section.required { "*" } else { " " };
            println!("  {marker} {:<16} {}", section.key, section.title);
        }
    }
    println!("\n* required section");
    Ok(())
}

fn run_note(args: NoteArgs) -> Result<()> {
    let text = read_text(&args.transcript)?;
    let encounter = build_encounter(&args.common);
    let pipeline = ScribePipeline::new()?;
    let output = pipeline.process_text(&encounter, &text)?;
    finish(&args.common, &encounter, output)
}

fn run_transcribe(args: TranscribeArgs) -> Result<()> {
    let audio = scribe_audio::load_wav(&args.audio)?;
    let encounter = build_encounter(&args.common);
    let mut pipeline = ScribePipeline::new()?;

    match args.engine.as_str() {
        "mock" => {}
        "whisper" => {
            let model = resolve_whisper_model()?;
            let engines = scribe_asr_whisper::WhisperAsrEngine::new(model, 4)?;
            pipeline = pipeline.with_asr(Box::new(engines));
        }
        other => {
            return Err(scribe_core::ScribeError::InvalidInput(format!(
                "unknown ASR engine '{other}'; this build ships 'mock' and 'whisper'. \
                 See docs/engineering/ASR.md for wiring a real engine."
            )));
        }
    }

    let options = scribe_pipeline::AsrOptions {
        language: Some("en".to_owned()),
        translate_to_english: false,
    };
    let output = pipeline.process_audio(&encounter, &audio, &options)?;

    eprintln!(
        "audio: {:.1}s · speech spans: {} · segments: {}",
        audio.duration_ms() as f64 / 1000.0,
        output.speech_spans.len(),
        output.transcript.segments.len()
    );

    finish(&args.common, &encounter, output)
}

/// Resolve the whisper model path: explicit env override, then the app's
/// standard download location. Mirrors the app's `ModelDownloader`.
fn resolve_whisper_model() -> Result<PathBuf> {
    if let Ok(explicit) = std::env::var("NOTA_WHISPER_MODEL") {
        return Ok(PathBuf::from(explicit));
    }
    let home = std::env::var("HOME")
        .map_err(|_| scribe_core::ScribeError::InvalidInput("HOME is not set".to_owned()))?;
    let path = PathBuf::from(home)
        .join("Library/Application Support/Klinote/Models")
        .join(scribe_asr_whisper::DEFAULT_MODEL_NAME);
    if path.is_file() {
        return Ok(path);
    }
    Err(scribe_core::ScribeError::InvalidInput(format!(
        "whisper model not found at {} — download it on first use, or set NOTA_WHISPER_MODEL",
        path.display()
    )))
}

fn run_audit(args: AuditArgs) -> Result<()> {
    let store = Store::open(&args.db)?;
    let trail = store.audit_trail(&args.subject)?;
    if trail.is_empty() {
        println!("no audit entries for subject '{}'", args.subject);
        return Ok(());
    }
    for entry in trail {
        println!(
            "{:>4}  {}  {:<16} {:<22} {}",
            entry.seq,
            entry.at,
            entry.action,
            entry.subject.unwrap_or_default(),
            entry.detail.unwrap_or_default()
        );
    }
    Ok(())
}

fn finish(
    common: &CommonArgs,
    encounter: &Encounter,
    output: scribe_pipeline::PipelineOutput,
) -> Result<()> {
    if let Some(db) = &common.db {
        let store = Store::open(db)?;
        store.save_encounter(encounter)?;
        store.save_transcript(&output.transcript)?;
        store.save_note(&output.note)?;
        store.audit(
            &common.actor,
            "note.generated",
            Some(&output.note.id.to_string()),
            Some(&format!("engine={}", output.note.engine)),
        )?;
    }

    let rendered = if common.json {
        serde_json::to_string_pretty(&output.note)?
    } else {
        output.note.to_markdown()
    };

    if let Some(path) = &common.out_transcript {
        let json = serde_json::to_string_pretty(&output.transcript)?;
        std::fs::write(path, json.as_bytes())?;
        eprintln!("wrote transcript {}", path.display());
    }

    match &common.out {
        Some(path) => {
            std::fs::write(path, rendered.as_bytes())?;
            eprintln!("wrote {}", path.display());
        }
        None => println!("{rendered}"),
    }

    // Always report engine provenance and completeness on stderr, so a
    // Markdown file piped to a colleague never loses its caveats.
    eprintln!(
        "note: {} · engine: {} · completeness: {:.0}%{}",
        output.note.id,
        output.note.engine,
        output.note.completeness() * 100.0,
        if output.note.missing_required.is_empty() {
            String::new()
        } else {
            format!(" · MISSING: {}", output.note.missing_required.join(", "))
        }
    );
    if output.note.engine == "mock" || output.transcript.engine == "mock" {
        eprintln!("⚠ mock ASR in use — text is synthetic, not a real transcription");
    }

    Ok(())
}

fn build_encounter(common: &CommonArgs) -> Encounter {
    let discipline = Discipline::from_key(&common.discipline);
    let mut encounter = Encounter::new(&common.patient_ref, discipline);
    encounter.template_id = TemplateId::new(&common.template);
    encounter.clinician_ref = common.clinician.clone();
    encounter
}

fn read_text(path: &str) -> Result<String> {
    if path == "-" {
        let mut buffer = String::new();
        std::io::stdin().read_to_string(&mut buffer)?;
        return Ok(buffer);
    }
    Ok(std::fs::read_to_string(path)?)
}
