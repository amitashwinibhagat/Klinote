use thiserror::Error;

/// Errors surfaced across the core. Deliberately coarse: the caller (CLI or
/// Swift shell) decides how to present them, and we never put patient data
/// into an error message.
#[derive(Debug, Error)]
pub enum ScribeError {
    #[error("template not found: {0}")]
    TemplateNotFound(String),

    #[error("invalid template '{id}': {reason}")]
    InvalidTemplate { id: String, reason: String },

    #[error("audio error: {0}")]
    Audio(String),

    #[error("transcription error: {0}")]
    Transcription(String),

    #[error("diarisation error: {0}")]
    Diarisation(String),

    #[error("note generation error: {0}")]
    NoteGeneration(String),

    #[error("storage error: {0}")]
    Storage(String),

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, ScribeError>;
