use std::collections::BTreeMap;
use std::path::Path;

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
];

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
