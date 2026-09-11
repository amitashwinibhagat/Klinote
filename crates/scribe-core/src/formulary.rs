//! On-device drug-name checks.
//!
//! Whisper mishears rare generics. The language model must **not** invent a
//! replacement (wrong real drug is worse than a nonsense word). We only
//! *suggest*, against a small GP formulary, and the clinician accepts.

use serde::{Deserialize, Serialize};

use crate::ids::SegmentId;
use crate::transcript::Transcript;

/// Heard in the transcript; a closer formulary name exists. Never auto-applied.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NameCheck {
    pub heard: String,
    pub suggest: String,
    #[serde(default)]
    pub evidence: Vec<SegmentId>,
}

/// Biases Whisper toward real generics. Keep short; this is decoder context.
pub const WHISPER_PROMPT: &str = "\
Medications: paracetamol ibuprofen cetirizine loratadine amoxicillin flucloxacillin \
metformin ramipril amlodipine atorvastatin salbutamol omeprazole prednisolone \
sertraline levothyroxine codeine tramadol naproxen doxycycline metronidazole.";

const FORMULARY: &[&str] = &[
    "paracetamol",
    "acetaminophen",
    "ibuprofen",
    "aspirin",
    "naproxen",
    "diclofenac",
    "cetirizine",
    "loratadine",
    "fexofenadine",
    "amoxicillin",
    "flucloxacillin",
    "penicillin",
    "doxycycline",
    "azithromycin",
    "clarithromycin",
    "metronidazole",
    "trimethoprim",
    "nitrofurantoin",
    "omeprazole",
    "lansoprazole",
    "pantoprazole",
    "ramipril",
    "amlodipine",
    "atorvastatin",
    "simvastatin",
    "metformin",
    "insulin",
    "salbutamol",
    "prednisolone",
    "hydrocortisone",
    "codeine",
    "tramadol",
    "morphine",
    "warfarin",
    "apixaban",
    "rivaroxaban",
    "clopidogrel",
    "sertraline",
    "fluoxetine",
    "citalopram",
    "levothyroxine",
    "diazepam",
    "co-codamol",
];

const STOP: &[&str] = &[
    "temperature",
    "examination",
    "situation",
    "parking",
    "morning",
    "patient",
    "doctor",
    "clinician",
    "allergy",
    "allergies",
    "infection",
    "history",
    "impression",
    "swallow",
    "throat",
    "chest",
    "pulse",
    "fever",
    "cough",
    "fluids",
    "tablet",
    "tablets",
    "capsule",
    "daily",
    "nothing",
    "anything",
    "something",
    "everything",
];

/// Scan transcript tokens. Exact formulary hits are left alone.
pub fn suggest(transcript: &Transcript) -> Vec<NameCheck> {
    let mut out = Vec::new();
    for segment in &transcript.segments {
        for token in tokens(&segment.text) {
            if token.chars().count() < 6 {
                continue;
            }
            if STOP.contains(&token.as_str()) {
                continue;
            }
            if FORMULARY.iter().any(|d| *d == token) {
                continue;
            }
            if let Some(drug) = best_match(&token) {
                if !out.iter().any(|c: &NameCheck| c.heard == token && c.suggest == drug)
                {
                    out.push(NameCheck {
                        heard: token,
                        suggest: drug,
                        evidence: vec![segment.id],
                    });
                }
            }
        }
    }
    out
}

fn tokens(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_ascii_alphabetic() && c != '-')
        .map(|t| t.trim_matches('-').to_ascii_lowercase())
        .filter(|t| t.chars().count() >= 6)
        .collect()
}

fn best_match(token: &str) -> Option<String> {
    let mut best: Option<(&str, usize, usize)> = None;
    for drug in FORMULARY {
        let lev = levenshtein(token, drug);
        let skel = levenshtein(&skeleton(token), &skeleton(drug));
        let score = lev.min(skel + 1);
        match best {
            None => best = Some((drug, lev, score)),
            Some((_, _, best_score)) if score < best_score => {
                best = Some((drug, lev, score));
            }
            _ => {}
        }
    }
    let (drug, lev, score) = best?;
    let ok = lev <= 2 || (score <= 2 && lev <= 4 && token.chars().count() >= 8);
    if ok {
        Some((*drug).to_owned())
    } else {
        None
    }
}

fn skeleton(word: &str) -> String {
    word.chars()
        .filter(|c| !matches!(c, 'a' | 'e' | 'i' | 'o' | 'u' | 'y'))
        .collect()
}

fn levenshtein(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut curr = vec![0; b.len() + 1];
    for (i, ca) in a.iter().enumerate() {
        curr[0] = i + 1;
        for (j, cb) in b.iter().enumerate() {
            let cost = usize::from(ca != cb);
            curr[j + 1] = (prev[j + 1] + 1).min(curr[j] + 1).min(prev[j] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[b.len()]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::{EncounterId, SpeakerId};
    use crate::transcript::{Segment, Transcript};

    fn transcript(text: &str) -> Transcript {
        let mut t = Transcript::new(EncounterId::new(), "test");
        t.push_segment(Segment::new(SpeakerId::CLINICIAN, 0, 1000, text));
        t
    }

    #[test]
    fn atyrazine_suggests_cetirizine() {
        let checks = suggest(&transcript("I take atyrazine for hay fever"));
        assert!(
            checks.iter().any(|c| c.heard == "atyrazine" && c.suggest == "cetirizine"),
            "{checks:?}"
        );
    }

    #[test]
    fn real_cetirizine_is_silent() {
        let checks = suggest(&transcript("I take cetirizine for hay fever"));
        assert!(checks.is_empty(), "{checks:?}");
    }

    #[test]
    fn situation_is_not_a_statin() {
        let checks = suggest(&transcript("the parking situation outside"));
        assert!(checks.is_empty(), "{checks:?}");
    }
}
