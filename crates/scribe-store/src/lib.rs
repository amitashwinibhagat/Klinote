//! Local storage.
//!
//! One SQLite file, no server, no sync. Transcripts and notes are stored as
//! JSON blobs so the schema can evolve without migrations on every field, and
//! every state change can be recorded in an append-only audit log.
//!
//! ## Not yet done, and knowingly so
//!
//! - **Encryption at rest.** SQLCipher. The Mac shell holds the key in the
//!   Keychain and passes it in on open. Never write the key next to the db.
//! - **Retention policy.** Rows are never deleted. The shell must offer
//!   per-practice retention and a real delete that also vacuums.

use std::path::Path;

use chrono::{DateTime, Utc};
use rusqlite::{Connection, OptionalExtension, params};
use scribe_core::{
    ClinicalNote, Discipline, Encounter, EncounterId, NoteId, Result, ScribeError, Transcript,
};

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
        Self::open_with_key(path, None)
    }

    /// `key` is a passphrase for SQLCipher. The Mac app passes a Keychain-held
    /// hex secret. CLI tools may omit it (unencrypted teaching fixtures only).
    pub fn open_with_key(path: impl AsRef<Path>, key: Option<&str>) -> Result<Self> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        retire_plaintext_sqlite(path)?;
        let conn = Connection::open(path).map_err(storage_error)?;
        if let Some(key) = key {
            if key.is_empty() {
                return Err(ScribeError::Storage("store key must not be empty".into()));
            }
            conn.pragma_update(None, "key", key)
                .map_err(storage_error)?;
        }
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

                -- What the consult asked the clinician to do. Not inferred:
                -- each row is a sentence the clinician's own note contains.
                CREATE TABLE IF NOT EXISTS tasks (
                    id           TEXT PRIMARY KEY,
                    encounter_id TEXT NOT NULL REFERENCES encounters(id) ON DELETE CASCADE,
                    text         TEXT NOT NULL,
                    source_key   TEXT,
                    created_at   TEXT NOT NULL,
                    done_at      TEXT,
                    UNIQUE(encounter_id, text)
                );

                CREATE INDEX IF NOT EXISTS idx_transcripts_encounter ON transcripts(encounter_id);
                CREATE INDEX IF NOT EXISTS idx_notes_encounter ON notes(encounter_id);
                CREATE INDEX IF NOT EXISTS idx_audit_subject ON audit_log(subject);
                CREATE INDEX IF NOT EXISTS idx_tasks_open ON tasks(done_at);
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

    /// Hard delete. Cascades transcripts and notes. Audit records the id, not the content.
    pub fn delete_encounter(&self, id: &str) -> Result<()> {
        let removed = self
            .conn
            .execute("DELETE FROM encounters WHERE id = ?1", params![id])
            .map_err(storage_error)?;
        if removed == 0 {
            return Err(ScribeError::Storage(format!("no encounter {id}")));
        }
        self.audit("shell", "encounter.deleted", Some(id), None)?;
        Ok(())
    }

    /// Add a task the consult asked for, ignoring one that already exists.
    /// Returns true when a new row was written.
    pub fn add_task(
        &self,
        encounter_id: &str,
        text: &str,
        source_key: Option<&str>,
    ) -> Result<bool> {
        let inserted = self
            .conn
            .execute(
                r#"INSERT INTO tasks (id, encounter_id, text, source_key, created_at)
                   VALUES (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4)
                   ON CONFLICT(encounter_id, text) DO NOTHING"#,
                params![encounter_id, text, source_key, Utc::now().to_rfc3339()],
            )
            .map_err(storage_error)?;
        Ok(inserted > 0)
    }

    /// Open tasks, oldest first, with the consult they came from.
    pub fn open_tasks(&self) -> Result<Vec<Task>> {
        let mut statement = self
            .conn
            .prepare(
                "SELECT id, encounter_id, text, source_key, created_at
                 FROM tasks WHERE done_at IS NULL ORDER BY created_at ASC",
            )
            .map_err(storage_error)?;
        let rows = statement
            .query_map([], |row| {
                Ok(Task {
                    id: row.get(0)?,
                    encounter_id: row.get(1)?,
                    text: row.get(2)?,
                    source_key: row.get(3)?,
                    created_at: row.get(4)?,
                    done: false,
                })
            })
            .map_err(storage_error)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(storage_error)
    }

    /// Every task for one consult, open or done, so the letter can show ticks.
    pub fn tasks_for(&self, encounter_id: &str) -> Result<Vec<Task>> {
        let mut statement = self
            .conn
            .prepare(
                "SELECT id, encounter_id, text, source_key, created_at, done_at
                 FROM tasks WHERE encounter_id = ?1 ORDER BY created_at ASC",
            )
            .map_err(storage_error)?;
        let rows = statement
            .query_map(params![encounter_id], |row| {
                Ok(Task {
                    id: row.get(0)?,
                    encounter_id: row.get(1)?,
                    text: row.get(2)?,
                    source_key: row.get(3)?,
                    created_at: row.get(4)?,
                    done: row.get::<_, Option<String>>(5)?.is_some(),
                })
            })
            .map_err(storage_error)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(storage_error)
    }

    /// Tick or untick. A task is a note to self, not a clinical record, so
    /// unticking is allowed.
    pub fn set_task_done(&self, id: &str, done: bool) -> Result<()> {
        let stamp = if done {
            Some(Utc::now().to_rfc3339())
        } else {
            None
        };
        let changed = self
            .conn
            .execute(
                "UPDATE tasks SET done_at = ?2 WHERE id = ?1",
                params![id, stamp],
            )
            .map_err(storage_error)?;
        if changed == 0 {
            return Err(ScribeError::Storage(format!("no task {id}")));
        }
        Ok(())
    }

    pub fn delete_task(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM tasks WHERE id = ?1", params![id])
            .map_err(storage_error)?;
        Ok(())
    }

    /// Hard-delete every encounter that started before `cutoff`.
    ///
    /// Retention is a statutory obligation, not a preference, so this is a real
    /// delete rather than a flag. Returns how many rows went. The audit entry
    /// records the count and the cutoff, never the content.
    pub fn delete_older_than(&self, cutoff: DateTime<Utc>) -> Result<usize> {
        let ids = {
            let mut statement = self
                .conn
                .prepare("SELECT id, started_at FROM encounters")
                .map_err(storage_error)?;
            let rows = statement
                .query_map([], |row| {
                    Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                })
                .map_err(storage_error)?;
            let mut stale = Vec::new();
            for row in rows {
                let (id, started_at) = row.map_err(storage_error)?;
                if let Ok(at) = DateTime::parse_from_rfc3339(&started_at)
                    && at.with_timezone(&Utc) < cutoff
                {
                    stale.push(id);
                }
            }
            stale
        };

        for id in &ids {
            self.conn
                .execute("DELETE FROM encounters WHERE id = ?1", params![id])
                .map_err(storage_error)?;
        }
        if !ids.is_empty() {
            self.audit(
                "shell",
                "encounter.purged",
                None,
                Some(&format!(
                    "count={} before={}",
                    ids.len(),
                    cutoff.to_rfc3339()
                )),
            )?;
        }
        Ok(ids.len())
    }

    /// Latest transcript and note for every encounter, newest first.
    pub fn list_sessions(&self) -> Result<Vec<StoredSession>> {
        let mut statement = self
            .conn
            .prepare(
                "SELECT id, patient_ref, clinician_ref, discipline, template_id,
                        started_at, ended_at, language, site_ref
                 FROM encounters ORDER BY started_at DESC",
            )
            .map_err(storage_error)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<String>>(7)?,
                    row.get::<_, Option<String>>(8)?,
                ))
            })
            .map_err(storage_error)?;

        let mut sessions = Vec::new();
        for row in rows {
            let (
                id,
                patient_ref,
                clinician_ref,
                discipline,
                template_id,
                started_at,
                ended_at,
                language,
                site_ref,
            ) = row.map_err(storage_error)?;
            let encounter_id: EncounterId = id
                .parse()
                .map_err(|err| ScribeError::Storage(format!("encounter id: {err}")))?;
            let started = chrono::DateTime::parse_from_rfc3339(&started_at)
                .map_err(|err| ScribeError::Storage(format!("started_at: {err}")))?
                .with_timezone(&Utc);
            let ended = ended_at
                .map(|value| {
                    chrono::DateTime::parse_from_rfc3339(&value)
                        .map(|dt| dt.with_timezone(&Utc))
                        .map_err(|err| ScribeError::Storage(format!("ended_at: {err}")))
                })
                .transpose()?;
            let mut encounter = Encounter::new(&patient_ref, Discipline::from_key(&discipline));
            encounter.id = encounter_id;
            encounter.clinician_ref = clinician_ref;
            encounter.template_id = scribe_core::TemplateId::new(template_id);
            encounter.started_at = started;
            encounter.ended_at = ended;
            encounter.language = language;
            encounter.site_ref = site_ref;

            let transcript = self.latest_transcript(encounter_id)?;
            let note = self.notes_for_encounter(encounter_id)?.into_iter().next();
            sessions.push(StoredSession {
                encounter,
                transcript,
                note,
            });
        }
        Ok(sessions)
    }

    fn latest_transcript(&self, id: EncounterId) -> Result<Option<Transcript>> {
        let json: Option<String> = self
            .conn
            .query_row(
                "SELECT json FROM transcripts WHERE encounter_id = ?1 ORDER BY id DESC LIMIT 1",
                params![id.to_string()],
                |row| row.get(0),
            )
            .optional()
            .map_err(storage_error)?;
        json.map(|json| serde_json::from_str(&json).map_err(store_json_error))
            .transpose()
    }
}

/// One thing a consult asked the clinician to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Task {
    pub id: String,
    pub encounter_id: String,
    pub text: String,
    pub source_key: Option<String>,
    pub created_at: String,
    pub done: bool,
}

/// One encounter plus its latest transcript and note, for the shell list.
#[derive(Debug, Clone)]
pub struct StoredSession {
    pub encounter: Encounter,
    pub transcript: Option<Transcript>,
    pub note: Option<ClinicalNote>,
}

/// Teaching-era files were plaintext SQLite. SQLCipher cannot open them.
/// Move aside rather than try to convert; those rows were never real patients.
fn retire_plaintext_sqlite(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let header = std::fs::read(path).map_err(|err| ScribeError::Storage(err.to_string()))?;
    if header.starts_with(b"SQLite format 3") {
        let backup = path.with_extension("sqlite.unencrypted-bak");
        std::fs::rename(path, backup).map_err(|err| ScribeError::Storage(err.to_string()))?;
    }
    Ok(())
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
        let sessions = store.list_sessions().unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].encounter.patient_ref, "patient-ref-opaque");
        assert!(sessions[0].transcript.is_some());
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
    fn deletes_an_encounter() {
        let store = Store::open_in_memory().unwrap();
        let encounter = encounter();
        store.save_encounter(&encounter).unwrap();
        store.delete_encounter(&encounter.id.to_string()).unwrap();
        assert_eq!(store.encounter_count().unwrap(), 0);
    }

    #[test]
    fn tasks_are_deduped_and_tickable() {
        let store = Store::open_in_memory().unwrap();
        let encounter = encounter();
        store.save_encounter(&encounter).unwrap();
        let id = encounter.id.to_string();

        assert!(
            store
                .add_task(&id, "Arrange a throat swab", Some("plan"))
                .unwrap()
        );
        // Re-drafting a note must not duplicate the same task.
        assert!(
            !store
                .add_task(&id, "Arrange a throat swab", Some("plan"))
                .unwrap()
        );
        assert!(store.add_task(&id, "Review in one week", None).unwrap());
        assert_eq!(store.open_tasks().unwrap().len(), 2);

        let first = store.open_tasks().unwrap().remove(0);
        store.set_task_done(&first.id, true).unwrap();
        assert_eq!(store.open_tasks().unwrap().len(), 1);
        // A task is a note to self: unticking is allowed.
        store.set_task_done(&first.id, false).unwrap();
        assert_eq!(store.open_tasks().unwrap().len(), 2);

        let for_encounter = store.tasks_for(&id).unwrap();
        assert_eq!(for_encounter.len(), 2);
        assert!(for_encounter.iter().all(|task| !task.done));
    }

    #[test]
    fn deleting_a_consult_takes_its_tasks() {
        let store = Store::open_in_memory().unwrap();
        let encounter = encounter();
        store.save_encounter(&encounter).unwrap();
        let id = encounter.id.to_string();
        store.add_task(&id, "Refer to ENT", None).unwrap();
        store.delete_encounter(&id).unwrap();
        assert!(store.open_tasks().unwrap().is_empty());
    }

    #[test]
    fn retention_deletes_only_old_encounters() {
        let store = Store::open_in_memory().unwrap();
        let mut old = encounter();
        old.started_at = Utc::now() - chrono::Duration::days(400);
        store.save_encounter(&old).unwrap();
        let fresh = encounter();
        store.save_encounter(&fresh).unwrap();

        let cutoff = Utc::now() - chrono::Duration::days(365);
        assert_eq!(store.delete_older_than(cutoff).unwrap(), 1);
        assert_eq!(store.encounter_count().unwrap(), 1);
        let remaining = store.list_sessions().unwrap();
        assert_eq!(remaining[0].encounter.id, fresh.id);
    }

    #[test]
    fn encrypted_file_is_not_plain_sqlite() {
        let path = std::env::temp_dir().join(format!("scribe-enc-{}.sqlite", std::process::id()));
        let _ = std::fs::remove_file(&path);
        {
            let store = Store::open_with_key(&path, Some("test-key-not-for-production")).unwrap();
            store.audit("test", "probe", None, None).unwrap();
        }
        let header = std::fs::read(&path).unwrap();
        assert!(
            !header.starts_with(b"SQLite format 3"),
            "ciphertext must not look like a sqlite file"
        );
        let _ = std::fs::remove_file(&path);
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
            render: Default::default(),
        }
    }
}
