//! Plain language for documents the patient reads.
//!
//! A patient's copy is not a note with a friendlier heading. Clinical shorthand
//! has to go, and there are three ways to deal with it:
//!
//! 1. **Expand it.** `tds` has exactly one meaning, so writing "three times a
//!    day" cannot add or remove a clinical fact. Safe to do automatically.
//! 2. **Flag it.** `od` is once-daily *and* right-eye. Rewriting it risks
//!    changing a clinical instruction, so it is surfaced, never guessed.
//! 3. **Leave it alone.** Everything else.
//!
//! The language model is asked to write plainly. This module exists because
//! asking is not a guarantee — a 4B model on a Q3 quant will leak `TID`
//! eventually, and a patient reading "400mg TID" is a real harm.

/// Definitional expansions. One meaning each; expanding is lossless.
const EXPAND: &[(&str, &str)] = &[
    ("bd", "twice a day"),
    ("bid", "twice a day"),
    ("tds", "three times a day"),
    ("tid", "three times a day"),
    ("qds", "four times a day"),
    ("qid", "four times a day"),
    ("prn", "as needed"),
    ("sos", "if needed"),
    ("nocte", "at night"),
    ("mane", "in the morning"),
    ("po", "by mouth"),
    ("q4h", "every 4 hours"),
    ("q6h", "every 6 hours"),
    ("q8h", "every 8 hours"),
    ("q12h", "every 12 hours"),
    ("mcg", "micrograms"),
    ("mg", "milligrams"),
    ("g", "grams"),
    ("ml", "millilitres"),
];

/// Shorthand a patient should not have to decode, and that cannot be expanded
/// safely because it is ambiguous out of context. Flagged, never rewritten.
const FLAG: &[&str] = &[
    "od", "os", "ou", "im", "iv", "sc", "hx", "sx", "dx", "rx", "pmh", "dhx", "fhx", "shx", "bp",
    "hr", "rr", "spo2", "bmi", "nad", "sob", "doe", "urti", "uti", "gerd", "copd", "t2dm", "t1dm",
    "cvd", "cva", "tia", "pe", "dvt", "lbp", "aki", "ckd", "af", "bp",
];

/// Expand what is safe to expand. Returns the rewritten text and the terms that
/// were expanded, so the change is visible rather than silent.
pub fn expand(text: &str) -> (String, Vec<String>) {
    let mut out = String::with_capacity(text.len());
    let mut expanded = Vec::new();
    let chars: Vec<char> = text.chars().collect();
    let mut index = 0;
    while index < chars.len() {
        if chars[index].is_ascii_alphanumeric() {
            let start = index;
            while index < chars.len() && chars[index].is_ascii_alphanumeric() {
                index += 1;
            }
            let token: String = chars[start..index].iter().collect();
            match expansion(&token) {
                Some(replacement) => {
                    out.push_str(replacement);
                    expanded.push(token);
                }
                None => out.push_str(&token),
            }
        } else {
            out.push(chars[index]);
            index += 1;
        }
    }
    (out, expanded)
}

/// Shorthand still present after expansion.
pub fn jargon_in(text: &str) -> Vec<String> {
    let mut found: Vec<String> = tokens(text)
        .into_iter()
        .filter(|token| FLAG.contains(&token.as_str()))
        .collect();
    found.sort();
    found.dedup();
    found
}

fn expansion(token: &str) -> Option<&'static str> {
    let lower = token.to_ascii_lowercase();
    // Never touch a token that is really a number with a unit ("400mg"), and
    // never expand a single letter, which is far more likely to be an initial.
    if token.chars().count() < 2 {
        return None;
    }
    if token.chars().any(|c| c.is_ascii_digit()) {
        return None;
    }
    EXPAND
        .iter()
        .find(|(abbreviation, _)| *abbreviation == lower)
        .map(|(_, replacement)| *replacement)
}

fn tokens(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        if chars[index].is_ascii_alphanumeric() {
            let start = index;
            while index < chars.len() && chars[index].is_ascii_alphanumeric() {
                index += 1;
            }
            out.push(
                chars[start..index]
                    .iter()
                    .collect::<String>()
                    .to_ascii_lowercase(),
            );
        } else {
            index += 1;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_dosing_frequency() {
        let (text, expanded) = expand("Ibuprofen 400mg tds with food");
        assert!(text.contains("three times a day"), "{text}");
        assert!(!text.contains("tds"));
        assert_eq!(expanded, vec!["tds"]);
        // A number with a unit is not an abbreviation.
        assert!(text.contains("400mg"), "{text}");
    }

    #[test]
    fn expands_the_common_latin_shorthand() {
        let (text, _) = expand("Paracetamol 1g qds prn. Salbutamol 2 puffs bd.");
        assert!(text.contains("four times a day"), "{text}");
        assert!(text.contains("as needed"), "{text}");
        assert!(text.contains("twice a day"), "{text}");
    }

    #[test]
    fn flags_ambiguous_shorthand_instead_of_guessing() {
        assert_eq!(jargon_in("Vision reduced in OD"), vec!["od"]);
        assert!(jargon_in("She has SOB and a UTI").contains(&"sob".to_owned()));
        // od is never rewritten: it is once-daily *and* right-eye.
        let (text, _) = expand("Vision reduced in OD");
        assert!(text.contains("OD"));
    }

    #[test]
    fn plain_language_is_untouched() {
        let (text, expanded) = expand("Take paracetamol four times a day as needed");
        assert_eq!(text, "Take paracetamol four times a day as needed");
        assert!(expanded.is_empty());
        assert!(jargon_in("Take paracetamol four times a day").is_empty());
    }
}
