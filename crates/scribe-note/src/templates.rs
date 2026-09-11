use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use scribe_core::{Result, ScribeError, Template, TemplateId};

/// The templates available to the app.
///
/// Built-ins are compiled in so the app always has a safe fallback; practices
/// can add or override templates from a directory on disk.
#[derive(Debug, Clone, Default)]
pub struct TemplateLibrary {
    templates: BTreeMap<TemplateId, Template>,
}

/// Templates compiled into the binary. Order does not matter.
const BUILTIN: &[(&str, &str)] = &[
    ("soap", include_str!("../../../templates/soap.toml")),
    (
        "physiotherapy",
        include_str!("../../../templates/physiotherapy.toml"),
    ),
    (
        "psychology",
        include_str!("../../../templates/psychology.toml"),
    ),
    (
        "dentistry",
        include_str!("../../../templates/dentistry.toml"),
    ),
    (
        "veterinary",
        include_str!("../../../templates/veterinary.toml"),
    ),
    // Documents the same consult already owes. Derived, never re-recorded.
    (
        "referral_letter",
        include_str!("../../../templates/referral_letter.toml"),
    ),
    (
        "patient_summary",
        include_str!("../../../templates/patient_summary.toml"),
    ),
];

/// A practice's template directory, or `KLINOTE_TEMPLATES_DIR` for tests and
/// for anyone keeping templates in a shared folder.
fn overrides_dir() -> Option<PathBuf> {
    if let Ok(explicit) = std::env::var("KLINOTE_TEMPLATES_DIR")
        && !explicit.trim().is_empty()
    {
        return Some(PathBuf::from(explicit));
    }
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join("Library/Application Support/Klinote/Templates"))
}

impl TemplateLibrary {
    pub fn builtin() -> Result<Self> {
        let mut library = Self::default();
        for (name, source) in BUILTIN {
            let template = Self::parse(name, source)?;
            library.insert(template)?;
        }
        Ok(library)
    }

    /// Parse a single template from TOML.
    pub fn parse(source_name: &str, source: &str) -> Result<Template> {
        let template: Template =
            toml::from_str(source).map_err(|err| ScribeError::InvalidTemplate {
                id: source_name.to_owned(),
                reason: err.to_string(),
            })?;
        template.validate()?;
        Ok(template)
    }

    /// Load every `*.toml` in a directory, overriding built-ins by id.
    /// A bad file is an error, not a silent skip — a malformed template is a
    /// clinical-safety problem.
    pub fn load_dir(dir: impl AsRef<Path>) -> Result<Self> {
        let mut library = Self::builtin()?;
        let dir = dir.as_ref();
        if !dir.is_dir() {
            return Err(ScribeError::InvalidInput(format!(
                "template directory does not exist: {}",
                dir.display()
            )));
        }

        let mut entries: Vec<_> = std::fs::read_dir(dir)?
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| path.extension().is_some_and(|ext| ext == "toml"))
            .collect();
        entries.sort();

        for path in entries {
            let source = std::fs::read_to_string(&path)?;
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("template")
                .to_owned();
            let template =
                Self::parse(&name, &source).map_err(|err| ScribeError::InvalidTemplate {
                    id: name.clone(),
                    reason: format!("{}: {err}", path.display()),
                })?;
            library.insert(template)?;
        }

        Ok(library)
    }

    /// Built-ins, plus any templates this practice has saved.
    ///
    /// A practice override lives as TOML next to the database, so a template a
    /// clinician edited survives an app update and can be read by hand,
    /// diffed, or put in a shared folder. A built-in with the same id is
    /// replaced; deleting the override restores it.
    pub fn for_this_machine() -> Result<Self> {
        let Some(dir) = overrides_dir() else {
            return Self::builtin();
        };
        if !dir.is_dir() {
            return Self::builtin();
        }
        Self::load_dir(dir)
    }

    /// Where a practice's own templates are written.
    pub fn overrides_dir() -> Option<PathBuf> {
        overrides_dir()
    }

    /// Write one template as TOML. The engine owns the file format so the app
    /// cannot drift from it.
    pub fn save_override(template: &Template) -> Result<PathBuf> {
        template.validate()?;
        let dir = overrides_dir().ok_or_else(|| {
            ScribeError::InvalidInput("no template directory on this machine".to_owned())
        })?;
        std::fs::create_dir_all(&dir)?;
        let body =
            toml::to_string_pretty(template).map_err(|err| ScribeError::InvalidTemplate {
                id: template.id.to_string(),
                reason: err.to_string(),
            })?;
        let path = dir.join(format!("{}.toml", template.id.as_str()));
        std::fs::write(&path, body)?;
        Ok(path)
    }

    /// Remove a practice override, restoring the built-in if there is one.
    pub fn delete_override(id: &str) -> Result<bool> {
        let Some(dir) = overrides_dir() else {
            return Ok(false);
        };
        let path = dir.join(format!("{id}.toml"));
        if !path.exists() {
            return Ok(false);
        }
        std::fs::remove_file(path)?;
        Ok(true)
    }

    pub fn insert(&mut self, template: Template) -> Result<()> {
        template.validate()?;
        self.templates.insert(template.id.clone(), template);
        Ok(())
    }

    pub fn get(&self, id: &str) -> Result<&Template> {
        let key = TemplateId::new(id);
        self.templates
            .get(&key)
            .ok_or_else(|| ScribeError::TemplateNotFound(id.to_owned()))
    }

    pub fn contains(&self, id: &str) -> bool {
        self.templates.contains_key(&TemplateId::new(id))
    }

    pub fn ids(&self) -> Vec<&str> {
        self.templates.keys().map(|id| id.as_str()).collect()
    }

    pub fn iter(&self) -> impl Iterator<Item = &Template> {
        self.templates.values()
    }

    pub fn len(&self) -> usize {
        self.templates.len()
    }

    pub fn is_empty(&self) -> bool {
        self.templates.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An override must survive a round trip through TOML and replace the
    /// built-in, and reverting must bring the built-in back.
    #[test]
    fn practise_override_round_trips() {
        let dir = std::env::temp_dir().join(format!("klinote-templates-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        // SAFETY: this test owns the variable; others do not read it.
        unsafe { std::env::set_var("KLINOTE_TEMPLATES_DIR", &dir) };

        let mut soap = TemplateLibrary::builtin()
            .unwrap()
            .get("soap")
            .unwrap()
            .clone();
        soap.name = "Our House SOAP".to_owned();
        soap.sections[0].cues.push("our-cue".to_owned());
        let path = TemplateLibrary::save_override(&soap).unwrap();
        assert!(path.exists());

        let loaded = TemplateLibrary::for_this_machine().unwrap();
        assert_eq!(loaded.get("soap").unwrap().name, "Our House SOAP");
        assert!(
            loaded.get("soap").unwrap().sections[0]
                .cues
                .contains(&"our-cue".to_owned())
        );
        // The other built-ins are still there.
        assert!(loaded.contains("referral_letter"));

        assert!(TemplateLibrary::delete_override("soap").unwrap());
        let restored = TemplateLibrary::for_this_machine().unwrap();
        assert_eq!(restored.get("soap").unwrap().name, "SOAP Note");

        let _ = std::fs::remove_dir_all(&dir);
        // SAFETY: as above.
        unsafe { std::env::remove_var("KLINOTE_TEMPLATES_DIR") };
    }

    #[test]
    fn builtins_parse_and_validate() {
        let library = TemplateLibrary::builtin().expect("built-in templates must be valid");
        assert!(library.len() >= 5);
        for id in [
            "soap",
            "physiotherapy",
            "psychology",
            "dentistry",
            "veterinary",
        ] {
            let template = library.get(id).unwrap();
            assert!(!template.sections.is_empty(), "{id} has no sections");
            assert!(
                !template.required_keys().is_empty(),
                "{id} has no required sections"
            );
        }
    }

    #[test]
    fn get_missing_template_is_an_error() {
        let library = TemplateLibrary::builtin().unwrap();
        let err = library.get("nope").unwrap_err();
        assert!(matches!(err, ScribeError::TemplateNotFound(_)));
    }

    #[test]
    fn malformed_template_is_rejected() {
        let err = TemplateLibrary::parse("broken", "id = \"broken\"\nname = \"x\"\n").unwrap_err();
        assert!(matches!(err, ScribeError::InvalidTemplate { .. }));
    }
}
