//! Local storage.
//!
//! One SQLite file, no server, no sync. Transcripts and notes are stored as
//! JSON blobs so the schema can evolve without migrations on every field, and
//! every state change can be recorded in an append-only audit log.
//!
//! ## Not yet done, and knowingly so
//!
//! - **Encryption at rest.** Today this relies on FileVault. Before any real
//!   patient data touches this, add SQLCipher (`rusqlite`'s
//!   `bundled-sqlcipher-vendored-openssl` feature) with a key held in the
//!   macOS Keychain. Tracked in `docs/compliance/PRIVACY.md`.
//! - **Retention policy.** Rows are never deleted. The shell must offer
//!   per-practice retention and a real delete that also vacuums.

use std::path::Path;

use chrono::Utc;
use rusqlite::{Connection, OptionalExtension, params};
use scribe_core::{ClinicalNote, Encounter, EncounterId, NoteId, Result, ScribeError, Transcript};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditEntry {
    pub seq: i64,
    pub at: String,
    pub actor: String,
    pub action: String,
    pub subject: Option<String>,
    pub detail: Option<String>,
}

pub struct Store {
    conn: Connection,
}

impl Store {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        let conn = Connection::open(path).map_err(storage_error)?;
        let store = Self { conn };
        store.migrate()?;
        Ok(store)
    }

    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory().map_err(storage_error)?;
        let store = Self { conn };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> Result<()> {
        self.conn
            .execute_batch(
                r#"
                PRAGMA journal_mode = WAL;
                PRAGMA foreign_keys = ON;

                CREATE TABLE IF NOT EXISTS encounters (
                    id            TEXT PRIMARY KEY,
                    patient_ref   TEXT NOT NULL,
                    clinician_ref TEXT,
                    discipline    TEXT NOT NULL,
                    template_id   TEXT NOT NULL,
                    started_at    TEXT NOT NULL,
                    ended_at      TEXT,
                    language      TEXT,
                    site_ref      TEXT,
                    created_at    TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS transcripts (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    encounter_id TEXT NOT NULL REFERENCES encounters(id) ON DELETE CASCADE,
                    engine       TEXT NOT NULL,
                    language     TEXT NOT NULL,
                    json         TEXT NOT NULL,
                    created_at   TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS notes (
                    id           TEXT PRIMARY KEY,
                    encounter_id TEXT NOT NULL REFERENCES encounters(id) ON DELETE CASCADE,
                    template_id  TEXT NOT NULL,
                    engine       TEXT NOT NULL,
                    review_state TEXT NOT NULL,
                    json         TEXT NOT NULL,
                    created_at   TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audit_log (
                    seq     INTEGER PRIMARY KEY AUTOINCREMENT,
                    at      TEXT NOT NULL,
                    actor   TEXT NOT NULL,
                    action  TEXT NOT NULL,
                    subject TEXT,
                    detail  TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_transcripts_encounter ON transcripts(encounter_id);
                CREATE INDEX IF NOT EXISTS idx_notes_encounter ON notes(encounter_id);
                CREATE INDEX IF NOT EXISTS idx_audit_subject ON audit_log(subject);
                "#,
            )
            .map_err(storage_error)
    }

    pub fn save_encounter(&self, encounter: &Encounter) -> Result<()> {
        self.conn
            .execute(
                r#"INSERT INTO encounters
                   (id, patient_ref, clinician_ref, discipline, template_id, started_at, ended_at, language, site_ref, created_at)
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                   ON CONFLICT(id) DO UPDATE SET
                     patient_ref = excluded.patient_ref,
                     clinician_ref = excluded.clinician_ref,
                     discipline = excluded.discipline,
                     template_id = excluded.template_id,
                     ended_at = excluded.ended_at,
                     language = excluded.language,
                     site_ref = excluded.site_ref"#,
                params![
                    encounter.id.to_string(),
                    encounter.patient_ref,
                    encounter.clinician_ref,
                    encounter.discipline.as_str(),
                    encounter.template_id.as_str(),
                    encounter.started_at.to_rfc3339(),
                    encounter.ended_at.map(|t| t.to_rfc3339()),
                    encounter.language,
                    encounter.site_ref,
                    Utc::now().to_rfc3339(),
                ],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn save_transcript(&self, transcript: &Transcript) -> Result<()> {
        let json = serde_json::to_string(transcript).map_err(store_json_error)?;
        self.conn
            .execute(
                r#"INSERT INTO transcripts (encounter_id, engine, language, json, created_at)
                   VALUES (?1, ?2, ?3, ?4, ?5)"#,
                params![
                    transcript.encounter_id.to_string(),
                    transcript.engine,
                    transcript.language,
                    json,
                    Utc::now().to_rfc3339(),
                ],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn save_note(&self, note: &ClinicalNote) -> Result<()> {
        let json = serde_json::to_string(note).map_err(store_json_error)?;
        self.conn
            .execute(
                r#"INSERT INTO notes (id, encounter_id, template_id, engine, review_state, json, created_at)
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                   ON CONFLICT(id) DO UPDATE SET
                     review_state = excluded.review_state,
                     json = excluded.json"#,
                params![
                    note.id.to_string(),
                    note.encounter_id.to_string(),
                    note.template_id.as_str(),
                    note.engine,
                    note.review_state.as_str(),
                    json,
                    Utc::now().to_rfc3339(),
                ],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn note(&self, id: NoteId) -> Result<Option<ClinicalNote>> {
        let json: Option<String> = self
            .conn
            .query_row(
                "SELECT json FROM notes WHERE id = ?1",
                params![id.to_string()],
                |row| row.get(0),
            )
            .optional()
            .map_err(storage_error)?;

        json.map(|json| serde_json::from_str(&json).map_err(store_json_error))
            .transpose()
    }

    pub fn notes_for_encounter(&self, id: EncounterId) -> Result<Vec<ClinicalNote>> {
        let mut statement = self
            .conn
            .prepare("SELECT json FROM notes WHERE encounter_id = ?1 ORDER BY created_at DESC")
            .map_err(storage_error)?;
        let rows = statement
            .query_map(params![id.to_string()], |row| row.get::<_, String>(0))
            .map_err(storage_error)?;

        let mut notes = Vec::new();
        for row in rows {
            let json = row.map_err(storage_error)?;
            notes.push(serde_json::from_str(&json).map_err(store_json_error)?);
        }
        Ok(notes)
    }

    /// Append to the audit log. This is the only immutability guarantee the
    /// store offers, and it is the one a clinic will ask about.
    pub fn audit(
        &self,
        actor: &str,
        action: &str,
        subject: Option<&str>,
        detail: Option<&str>,
    ) -> Result<()> {
        self.conn
            .execute(
                "INSERT INTO audit_log (at, actor, action, subject, detail) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![Utc::now().to_rfc3339(), actor, action, subject, detail],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn audit_trail(&self, subject: &str) -> Result<Vec<AuditEntry>> {
        let mut statement = self
            .conn
            .prepare(
                "SELECT seq, at, actor, action, subject, detail FROM audit_log
                 WHERE subject = ?1 ORDER BY seq ASC",
            )
            .map_err(storage_error)?;
        let rows = statement
            .query_map(params![subject], |row| {
                Ok(AuditEntry {
                    seq: row.get(0)?,
                    at: row.get(1)?,
                    actor: row.get(2)?,
                    action: row.get(3)?,
                    subject: row.get(4)?,
                    detail: row.get(5)?,
                })
            })
            .map_err(storage_error)?;

        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(storage_error)
    }

    pub fn encounter_count(&self) -> Result<i64> {
        self.conn
            .query_row("SELECT COUNT(*) FROM encounters", [], |row| row.get(0))
            .map_err(storage_error)
    }
}

fn storage_error(err: rusqlite::Error) -> ScribeError {
    ScribeError::Storage(err.to_string())
}

fn store_json_error(err: serde_json::Error) -> ScribeError {
    ScribeError::Storage(format!("json: {err}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use scribe_core::{Discipline, ReviewState, Speaker, SpeakerId, SpeakerRole};

    fn encounter() -> Encounter {
        Encounter::new("patient-ref-opaque", Discipline::GeneralPractice)
    }

    fn transcript(encounter: &Encounter) -> Transcript {
        let mut transcript = Transcript::new(encounter.id, "test");
        transcript.push_speaker(Speaker::new(SpeakerId::CLINICIAN, SpeakerRole::Clinician));
        transcript.push_segment(scribe_core::Segment::new(
            SpeakerId::CLINICIAN,
            0,
            1000,
            "hello",
        ));
        transcript
    }

    #[test]
    fn round_trips_encounter_and_transcript() {
        let store = Store::open_in_memory().unwrap();
        let encounter = encounter();
        store.save_encounter(&encounter).unwrap();
        store.save_transcript(&transcript(&encounter)).unwrap();
        assert_eq!(store.encounter_count().unwrap(), 1);
    }

    #[test]
    fn round_trips_a_note() {
        let store = Store::open_in_memory().unwrap();
        let encounter = encounter();
        store.save_encounter(&encounter).unwrap();

        let pipeline = scribe_pipeline_stub_note(&encounter);
        store.save_note(&pipeline).unwrap();

        let loaded = store.note(pipeline.id).unwrap().unwrap();
        assert_eq!(loaded.id, pipeline.id);
        assert_eq!(loaded.encounter_id, encounter.id);
        assert_eq!(loaded.review_state, ReviewState::Draft);
    }

    #[test]
    fn audit_log_is_append_only_and_queryable() {
        let store = Store::open_in_memory().unwrap();
        store
            .audit("clinician:1", "note.generated", Some("note-1"), None)
            .unwrap();
        store
            .audit(
                "clinician:1",
                "note.approved",
                Some("note-1"),
                Some("signed"),
            )
            .unwrap();
        store
            .audit("clinician:1", "note.generated", Some("note-2"), None)
            .unwrap();

        let trail = store.audit_trail("note-1").unwrap();
        assert_eq!(trail.len(), 2);
        assert_eq!(trail[0].action, "note.generated");
        assert_eq!(trail[1].action, "note.approved");
        assert!(trail[0].seq < trail[1].seq);
    }

    // Minimal note construction so this crate does not depend on scribe-note.
    fn scribe_pipeline_stub_note(encounter: &Encounter) -> ClinicalNote {
        ClinicalNote {
            id: NoteId::new(),
            encounter_id: encounter.id,
            template_id: encounter.template_id.clone(),
            sections: Vec::new(),
            unassigned: Vec::new(),
            generated_at: Utc::now(),
            engine: "test".to_owned(),
            review_state: ReviewState::Draft,
            missing_required: Vec::new(),
            machine_generated: true,
        }
    }
}
