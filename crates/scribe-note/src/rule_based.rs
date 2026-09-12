use std::collections::BTreeMap;

use scribe_core::{
    ClinicalNote, NoteId, NoteSection, NoteSentence, Result, ReviewState, SectionSpec, SegmentId,
    SpeakerRole, Support, Template, UnassignedItem,
};

use crate::generator::{GenerationRequest, NoteGenerator};

/// Deterministic, offline, model-free note generator.
///
/// This is the v0 engine and it is not a placeholder: it produces a usable
/// structured draft from a transcript today, with no model download, no
/// latency budget, and every sentence traceable to a transcript segment.
///
/// Its job is to make the *structure* and the *completeness check* correct.
/// A model-backed generator can later replace the routing while keeping the
/// same template contract — and this one remains the fallback when no model is
/// available, which matters in a clinic with no download budget.
#[derive(Debug, Default, Clone, Copy)]
pub struct RuleBasedGenerator;

impl NoteGenerator for RuleBasedGenerator {
    fn name(&self) -> &str {
        "rule-based-v1"
    }

    fn generate(&self, request: &GenerationRequest<'_>) -> Result<ClinicalNote> {
        let template = request.template;

        let mut routed: BTreeMap<&str, Vec<Scored>> = BTreeMap::new();
        let mut unassigned: Vec<UnassignedItem> = Vec::new();

        for section in &template.sections {
            routed.insert(section.key.as_str(), Vec::new());
        }

        for segment in &request.transcript.segments {
            let role = request.transcript.role_of(segment.speaker);
            for raw_sentence in split_sentences(&segment.text) {
                let sentence = tidy(raw_sentence);
                if sentence.split_whitespace().count() < 2 {
                    continue;
                }

                // A question is an interview artefact, not a finding. "Any
                // fever or cough?" documents nothing; the answer does. Filing
                // questions padded the history of every letter.
                if sentence.trim_end().ends_with('?') {
                    unassigned.push(UnassignedItem {
                        text: sentence,
                        speaker_role: role.as_str().to_owned(),
                        evidence: vec![segment.id],
                    });
                    continue;
                }

                match route(&sentence, role, template) {
                    Some((key, ambiguous)) => {
                        if let Some(bucket) = routed.get_mut(key) {
                            // Keep the source segment with the sentence so the
                            // note can cite it sentence by sentence.
                            bucket.push(Scored {
                                text: sentence,
                                segment_id: segment.id,
                                ambiguous,
                            });
                        }
                    }
                    None => unassigned.push(UnassignedItem {
                        text: sentence,
                        speaker_role: role.as_str().to_owned(),
                        evidence: vec![segment.id],
                    }),
                }
            }
        }

        let mut sections = Vec::with_capacity(template.sections.len());
        let mut missing_required = Vec::new();

        for spec in &template.sections {
            let key = spec.key.as_str();
            let entries = routed.remove(key).unwrap_or_default();

            let sentences: Vec<NoteSentence> = entries
                .iter()
                .map(|entry| NoteSentence {
                    text: entry.text.clone(),
                    evidence: vec![entry.segment_id],
                    ambiguous: entry.ambiguous,
                    support: Support::Supported,
                    wording: Default::default(),
                })
                .collect();

            let body = sentences
                .iter()
                .map(|sentence| sentence.text.as_str())
                .collect::<Vec<_>>()
                .join(" ");

            let mut ids: Vec<SegmentId> = entries.iter().map(|entry| entry.segment_id).collect();
            ids.dedup();

            let complete = !body.trim().is_empty();
            if spec.required && !complete {
                missing_required.push(spec.key.clone());
            }

            sections.push(NoteSection {
                key: spec.key.clone(),
                title: spec.title.clone(),
                body,
                evidence: ids,
                sentences,
                complete,
            });
        }

        Ok(ClinicalNote {
            id: NoteId::new(),
            encounter_id: request.encounter.id,
            template_id: template.id.clone(),
            sections,
            unassigned,
            generated_at: chrono::Utc::now(),
            engine: self.name().to_owned(),
            review_state: ReviewState::Draft,
            missing_required,
            machine_generated: true,
            render: template.render,
        })
    }
}

/// Sections that patient or caregiver speech should default into when no cue
/// gives a stronger signal.
const PATIENT_PREFERRED: &[&str] = &["subjective", "history", "presenting", "chief_complaint"];

/// Pick a section for a sentence. Returns `None` when nothing matches
/// confidently — the caller files it as unassigned rather than guessing.
/// A sentence placed in a section, with whether the placement was contested.
///
/// `ambiguous` is not decoration: two sections scoring the same means the
/// router does not know either, and a clinician should look at that line
/// rather than trust it.
struct Scored {
    text: String,
    segment_id: SegmentId,
    ambiguous: bool,
}

fn route<'a>(sentence: &str, role: SpeakerRole, template: &'a Template) -> Option<(&'a str, bool)> {
    let mut scored: Vec<(&str, u32)> = Vec::new();

    for spec in &template.sections {
        let mut score = score_section(sentence, spec, template);
        if score == 0 {
            continue;
        }
        if matches!(role, SpeakerRole::Patient | SpeakerRole::Caregiver)
            && PATIENT_PREFERRED.contains(&spec.key.as_str())
        {
            score += 3;
        }
        scored.push((spec.key.as_str(), score));
    }

    // Sort is stable, so equal scores keep template order — deterministic.
    scored.sort_by_key(|(_, score)| std::cmp::Reverse(*score));

    if let Some((key, best)) = scored.first().copied() {
        let second = scored.get(1).map(|(_, score)| *score).unwrap_or(0);
        // A near-tie is a coin toss dressed as a decision. Say so.
        let ambiguous = second > 0 && best.saturating_sub(second) <= 1;
        return Some((key, ambiguous));
    }

    // A patient statement with no cue match still belongs in the history if
    // the template has one — dropping it would be worse than filing it.
    if matches!(role, SpeakerRole::Patient | SpeakerRole::Caregiver) {
        return template
            .sections
            .iter()
            .find(|s| PATIENT_PREFERRED.contains(&s.key.as_str()))
            .map(|s| (s.key.as_str(), false));
    }

    None
}

/// How many sections share this cue. A cue that appears everywhere ("mg",
/// "plan") separates nothing, so it stops counting.
fn cue_rarity(cue: &str, template: &Template) -> u32 {
    let needle = normalize_for_match(cue);
    let mut sharing = 0;
    for spec in &template.sections {
        if spec
            .cues
            .iter()
            .any(|candidate| normalize_for_match(candidate) == needle)
        {
            sharing += 1;
        }
    }
    match sharing {
        1 => 2,
        2 => 1,
        _ => 0,
    }
}

fn score_section(sentence: &str, spec: &SectionSpec, template: &Template) -> u32 {
    let haystack = normalize_for_match(sentence);
    if haystack.is_empty() {
        return 0;
    }
    let tokens = tokenize(&haystack);

    let mut score = 0u32;
    for cue in &spec.cues {
        let needle = normalize_for_match(cue);
        if needle.is_empty() {
            continue;
        }
        // A cue every section has cannot separate them. Weight what is
        // distinctive; ignore what is not.
        let rarity = cue_rarity(&needle, template);
        if rarity == 0 {
            continue;
        }

        if needle.contains(' ') {
            if haystack.contains(&needle) {
                // Multi-word matches are stronger evidence than single tokens.
                score += (3 + needle.split_whitespace().count() as u32) * rarity;
            }
            continue;
        }

        if tokens.iter().any(|token| *token == needle) {
            score += 3 * rarity;
            continue;
        }

        // "500mg" should match the cue "mg"; "spo2" should not become "spo".
        if needle.chars().all(|c| c.is_ascii_alphabetic())
            && tokens.iter().any(|token| {
                token.len() > needle.len()
                    && token.ends_with(needle.as_str())
                    && token[..token.len() - needle.len()]
                        .chars()
                        .all(|c| c.is_ascii_digit())
            })
        {
            score += 2 * rarity;
        }
    }

    score
}

/// Split into sentences on terminal punctuation and newlines.
///
/// Two deliberate details: the terminal character is kept on the sentence so
/// a question stays a question, and a period between two digits (`37.4`) is
/// not a sentence boundary.
fn split_sentences(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let bytes = text.as_bytes();
    let mut start = 0usize;
    let mut index = 0usize;

    while index < bytes.len() {
        let byte = bytes[index];
        let cut = match byte {
            b'\n' | b';' => true,
            b'.' => {
                let prev_digit = index > 0 && bytes[index - 1].is_ascii_digit();
                let next_digit = bytes.get(index + 1).is_some_and(u8::is_ascii_digit);
                !(prev_digit && next_digit)
            }
            b'?' | b'!' => true,
            _ => false,
        };

        if cut {
            let end = if matches!(byte, b'.' | b'?' | b'!') {
                index + 1
            } else {
                index
            };
            let slice = text[start..end].trim();
            if !slice.is_empty() {
                out.push(slice);
            }
            start = index + 1;
        }

        index += 1;
    }

    if start < text.len() {
        let tail = &text[start..];
        if !tail.trim().is_empty() {
            out.push(tail);
        }
    }

    out
}

/// Remove filler and hesitation noise, collapse stutters, fix casing and
/// ensure terminal punctuation.
///
/// Punctuation *inside* a sentence is preserved — a clinical note that loses
/// its commas reads worse, not cleaner.
pub fn tidy(sentence: &str) -> String {
    const FILLERS: &[&str] = &["um", "uh", "erm", "er", "ah", "hmm", "mmm", "mm", "eh"];
    const TRIM: &[char] = &['"', '\'', '(', ')', '[', ']', '“', '”', '‘', '’'];

    let mut words: Vec<String> = Vec::new();

    for raw in sentence.split_whitespace() {
        let token = raw.trim_matches(|c: char| TRIM.contains(&c));
        let key = token
            .trim_matches(|c: char| !c.is_alphanumeric())
            .to_ascii_lowercase();
        if key.is_empty() || FILLERS.contains(&key.as_str()) {
            continue;
        }

        // Collapse immediate stutters: "the the patient" -> "the patient".
        if let Some(previous) = words.last() {
            let previous_key = previous
                .trim_matches(|c: char| !c.is_alphanumeric())
                .to_ascii_lowercase();
            if previous_key == key {
                continue;
            }
        }

        words.push(token.to_owned());
    }

    if words.is_empty() {
        return String::new();
    }

    let mut out = fix_casing(&words.join(" "));
    // A dangling comma or colon at the end of a fragment reads as an error;
    // internal punctuation is kept.
    let trimmed = out.trim_end_matches([',', ';', ':']).trim_end();
    out = trimmed.to_owned();
    if !out.ends_with(['.', '?', '!']) {
        out.push('.');
    }
    out
}

fn fix_casing(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    let mut capitalize_next = true;

    for word in text.split(' ') {
        if !result.is_empty() {
            result.push(' ');
        }
        if capitalize_next && !word.is_empty() {
            let mut chars = word.chars();
            if let Some(first) = chars.next() {
                result.extend(first.to_uppercase());
                result.push_str(chars.as_str());
            }
            capitalize_next = false;
        } else if word == "i" {
            result.push('I');
        } else if word.eq_ignore_ascii_case("i'm")
            || word.eq_ignore_ascii_case("i've")
            || word.eq_ignore_ascii_case("i'll")
            || word.eq_ignore_ascii_case("i'd")
        {
            let mut chars = word.chars();
            if let Some(first) = chars.next() {
                result.extend(first.to_uppercase());
                result.push_str(chars.as_str());
            }
        } else {
            result.push_str(word);
        }

        if word.ends_with(['.', '?', '!']) {
            capitalize_next = true;
        }
    }

    result
}

fn normalize_for_match(text: &str) -> String {
    text.to_ascii_lowercase()
        .replace(['\'', '\u{2019}'], "")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn tokenize(normalized: &str) -> Vec<&str> {
    normalized
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|token| !token.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::templates::TemplateLibrary;
    use scribe_core::{
        Discipline, Encounter, Segment, Speaker, SpeakerId, Transcript, parse_transcript_text,
    };

    fn generate(template_id: &str, transcript_text: &str) -> ClinicalNote {
        let library = TemplateLibrary::builtin().unwrap();
        let template = library.get(template_id).unwrap();
        let encounter = Encounter::new("test-patient", Discipline::GeneralPractice);
        let transcript = parse_transcript_text(transcript_text, encounter.id, "en").unwrap();
        let generator = RuleBasedGenerator;
        generator
            .generate(&GenerationRequest {
                encounter: &encounter,
                transcript: &transcript,
                template,
            })
            .unwrap()
    }

    const GP_DIALOGUE: &str = "\
CLINICIAN: Good morning, what brings you in today?
PATIENT: I have had a sore throat for four days and it hurts when I swallow.
CLINICIAN: Any fever or cough?
PATIENT: No fever, but I have been feeling tired.
CLINICIAN: On examination your temperature is 37.2 and your throat shows erythema with enlarged tonsils.
CLINICIAN: Chest is clear on auscultation.
CLINICIAN: My impression is a viral upper respiratory tract infection.
CLINICIAN: Plan: rest and fluids, paracetamol 1g four times a day as needed.
CLINICIAN: Follow up in one week if not improving.
";

    #[test]
    fn routes_general_practice_dialogue_into_soap() {
        let note = generate("soap", GP_DIALOGUE);

        let subjective = note.section("subjective").unwrap();
        assert!(
            subjective.body.to_lowercase().contains("sore throat"),
            "{}",
            subjective.body
        );

        let objective = note.section("objective").unwrap();
        assert!(
            objective.body.to_lowercase().contains("temperature"),
            "{}",
            objective.body
        );
        assert!(
            objective.body.to_lowercase().contains("auscultation"),
            "{}",
            objective.body
        );

        let assessment = note.section("assessment").unwrap();
        assert!(
            assessment.body.to_lowercase().contains("viral"),
            "{}",
            assessment.body
        );

        let plan = note.section("plan").unwrap();
        assert!(
            plan.body.to_lowercase().contains("paracetamol"),
            "{}",
            plan.body
        );
        assert!(!plan.is_empty(), "plan should be complete");

        assert!(
            note.missing_required.is_empty(),
            "unexpected missing: {:?}",
            note.missing_required
        );
    }

    #[test]
    fn flags_missing_required_sections() {
        let note = generate(
            "soap",
            "CLINICIAN: Patient reports a headache since yesterday.",
        );
        assert!(note.missing_required.contains(&"objective".to_owned()));
        assert!(note.missing_required.contains(&"assessment".to_owned()));
        assert!(note.missing_required.contains(&"plan".to_owned()));
        assert!(!note.missing_required.contains(&"subjective".to_owned()));
    }

    #[test]
    fn never_drops_transcript_content() {
        let library = TemplateLibrary::builtin().unwrap();
        let template = library.get("soap").unwrap();
        let encounter = Encounter::new("p", Discipline::GeneralPractice);

        let mut transcript = Transcript::new(encounter.id, "test");
        transcript.push_speaker(Speaker::new(SpeakerId::CLINICIAN, SpeakerRole::Clinician));
        // Deliberately unmatchable clinician prose.
        transcript.push_segment(Segment::new(
            SpeakerId::CLINICIAN,
            0,
            2000,
            "The weather was unusually warm for the season and the traffic was awful.",
        ));

        let note = RuleBasedGenerator
            .generate(&GenerationRequest {
                encounter: &encounter,
                transcript: &transcript,
                template,
            })
            .unwrap();

        assert_eq!(note.unassigned.len(), 1);
        assert!(note.unassigned[0].text.to_lowercase().contains("weather"));
    }

    #[test]
    fn every_sentence_carries_its_own_evidence() {
        let note = generate(
            "soap",
            "CLINICIAN: On examination the throat shows erythema.\n\
             CLINICIAN: Chest is clear on auscultation.",
        );
        let objective = note.section("objective").unwrap();
        assert_eq!(objective.sentences.len(), 2, "{objective:?}");
        for sentence in &objective.sentences {
            assert_eq!(
                sentence.evidence.len(),
                1,
                "sentence without its own evidence: {sentence:?}"
            );
        }
        // The two sentences came from two different transcript segments.
        assert_ne!(
            objective.sentences[0].evidence[0],
            objective.sentences[1].evidence[0]
        );
        // `body` stays the joined sentences, so Markdown output is unchanged.
        assert_eq!(
            objective.body,
            objective
                .sentences
                .iter()
                .map(|s| s.text.as_str())
                .collect::<Vec<_>>()
                .join(" ")
        );
    }

    #[test]
    fn tidies_filler_and_casing() {
        assert_eq!(
            tidy("um so i have a sore throat"),
            "So I have a sore throat."
        );
        assert_eq!(tidy("uh the the pain is here"), "The pain is here.");
    }

    #[test]
    fn preserves_decimals_and_question_marks() {
        let parts = split_sentences("Temperature is 37.4 today. Any fever? No, none at all.");
        assert_eq!(parts.len(), 3, "{parts:?}");
        assert_eq!(parts[0], "Temperature is 37.4 today.");
        assert_eq!(parts[1], "Any fever?");
        assert!(tidy(parts[1]).ends_with('?'));
    }

    #[test]
    fn keeps_internal_commas() {
        assert_eq!(
            tidy("Good morning, come in and sit down,"),
            "Good morning, come in and sit down."
        );
    }

    #[test]
    fn matches_units_attached_to_numbers() {
        let template = TemplateLibrary::builtin().unwrap();
        let soap = template.get("soap").unwrap();
        let plan = soap.section("plan").unwrap();
        assert!(score_section("Amoxicillin 500mg three times a day", plan, soap) > 0);
    }
}
