//! Sentence-level grounding checks.
//!
//! The strongest trust a local scribe can offer is a mechanical check: does the
//! sentence's own evidence actually contain what the sentence claims? Prose
//! overlap is a bad test — every useful note paraphrases. Two things are not
//! paraphrase, and those are what we check:
//!
//! 1. **Numbers.** `37.4`, `88`, `400mg`, `1g`, `4 days`. If a figure appears in
//!    the note and not in the words that were heard, a clinician must look.
//! 2. **Drug names.** A medicine in the note that nobody said is the exact
//!    failure mode that makes clinicians refuse these tools.
//!
//! A sentence with no evidence at all is unverified by definition. Everything
//! else passes. This is a review prompt, not an error: it never blocks, never
//! rewrites, and never claims the sentence is wrong.

use std::collections::HashSet;

use crate::formulary;
use crate::note::Support;

/// Judge one sentence against the transcript text it cites.
pub fn judge(sentence: &str, cited: &str) -> Support {
    if cited.trim().is_empty() {
        return Support::Unverified;
    }
    let cited_numbers = numbers(cited);
    for number in numbers(sentence) {
        if !cited_numbers.contains(&number) {
            return Support::Unverified;
        }
    }
    let cited_lower = cited.to_ascii_lowercase();
    for drug in drugs(sentence) {
        if !cited_lower.contains(&drug) {
            return Support::Unverified;
        }
    }
    Support::Supported
}

/// Formulary names that appear in `text`.
pub fn drugs(text: &str) -> Vec<String> {
    let mut out: Vec<String> = formulary::tokens_of(text)
        .into_iter()
        .filter(|token| formulary::is_known_drug(token))
        .collect();
    out.sort();
    out.dedup();
    out
}

/// Numeric values in `text`, with spoken forms folded to digits so that
/// "thirty seven point four" and "37.4" compare equal, and "four times" and
/// "q4h" agree.
///
/// Speech recognition writes numbers as words ("eighty eight", "four hundred
/// milligrams"), while a drafted note writes digits ("88", "400mg"). Comparing
/// the two requires reading the words as numbers, not just extracting digits.
pub fn numbers(text: &str) -> HashSet<String> {
    let tokens = formulary::tokens_of(text);
    let mut out = HashSet::new();
    let mut index = 0;
    while index < tokens.len() {
        let token = &tokens[index];
        if token.chars().any(|c| c.is_ascii_digit()) {
            for value in digits_in(token) {
                out.insert(value);
            }
            index += 1;
        } else if let Some((value, next)) = spoken_number(&tokens, index) {
            out.insert(value);
            index = next;
        } else {
            index += 1;
        }
    }
    out
}

fn digits_in(token: &str) -> Vec<String> {
    let chars: Vec<char> = token.chars().collect();
    let mut out = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        if chars[index].is_ascii_digit() {
            let start = index;
            while index < chars.len() && (chars[index].is_ascii_digit() || chars[index] == '.') {
                index += 1;
            }
            let mut value: String = chars[start..index].iter().collect();
            while value.ends_with('.') {
                value.pop();
            }
            if !value.is_empty() {
                out.push(value);
            }
        } else {
            index += 1;
        }
    }
    out
}

fn unit_value(token: &str) -> Option<u64> {
    Some(match token {
        "zero" => 0,
        "one" => 1,
        "two" => 2,
        "three" => 3,
        "four" => 4,
        "five" => 5,
        "six" => 6,
        "seven" => 7,
        "eight" => 8,
        "nine" => 9,
        "ten" => 10,
        "eleven" => 11,
        "twelve" => 12,
        "thirteen" => 13,
        "fourteen" => 14,
        "fifteen" => 15,
        "sixteen" => 16,
        "seventeen" => 17,
        "eighteen" => 18,
        "nineteen" => 19,
        _ => return None,
    })
}

fn tens_value(token: &str) -> Option<u64> {
    Some(match token {
        "twenty" => 20,
        "thirty" => 30,
        "forty" => 40,
        "fifty" => 50,
        "sixty" => 60,
        "seventy" => 70,
        "eighty" => 80,
        "ninety" => 90,
        _ => return None,
    })
}

/// Read a spoken number starting at `start`. Handles "eighty eight", "four
/// hundred and fifty", "thirty seven point four". Returns the value and the
/// index after it.
fn spoken_number(tokens: &[String], start: usize) -> Option<(String, usize)> {
    let mut value: u64 = 0;
    let mut index = start;
    let mut seen = false;
    let mut scale: u64 = 1;

    while index < tokens.len() {
        let token = tokens[index].as_str();
        if token == "and" && seen {
            index += 1;
            continue;
        }
        if let Some(unit) = unit_value(token) {
            value += unit * scale;
            seen = true;
            index += 1;
        } else if let Some(tens) = tens_value(token) {
            value += tens * scale;
            seen = true;
            index += 1;
        } else if token == "hundred" {
            value = value.max(1) * 100;
            seen = true;
            index += 1;
        } else if token == "thousand" {
            value = value.max(1) * 1000;
            seen = true;
            index += 1;
        } else if token == "point" && seen {
            index += 1;
            let mut fraction = String::new();
            while index < tokens.len() {
                let current = tokens[index].as_str();
                if let Some(unit) = unit_value(current) {
                    fraction.push_str(&unit.to_string());
                    index += 1;
                } else if current.chars().all(|c| c.is_ascii_digit()) {
                    fraction.push_str(current);
                    index += 1;
                } else {
                    break;
                }
            }
            return Some((format!("{value}.{fraction}"), index));
        } else {
            break;
        }
        if value > 1_000_000 {
            scale = 1;
        }
    }

    if seen {
        Some((value.to_string(), index))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matching_numbers_are_supported() {
        assert_eq!(
            judge(
                "Temp 37.4, pulse 88.",
                "your temperature is 37.4, pulse 88 and regular"
            ),
            Support::Supported
        );
    }

    #[test]
    fn word_and_digit_forms_agree() {
        assert_eq!(
            judge(
                "Sore throat x4d.",
                "I've had a sore throat for about four days"
            ),
            Support::Supported
        );
        assert_eq!(
            judge(
                "Paracetamol 1g qds.",
                "paracetamol 1g four times a day as needed"
            ),
            Support::Supported
        );
    }

    #[test]
    fn spoken_numbers_match_digits() {
        // What whisper actually produced from the GP tape: numbers as words.
        let heard = "your temperature is thirty seven point four, pulse eighty eight and regular";
        assert_eq!(
            judge("Temp 37.4°C, HR 88 bpm, regular.", heard),
            Support::Supported
        );
        assert_eq!(
            judge(
                "Paracetamol 1g q4h. Ibuprofen 400mg tds.",
                "paracetamol one gram four times a day and ibuprofen four hundred milligrams three times a day"
            ),
            Support::Supported
        );
    }

    #[test]
    fn wrong_dosing_interval_is_unverified() {
        // Quire wrote q6h where the clinician said three times a day.
        assert_eq!(
            judge(
                "Ibuprofen 400mg q6h with food.",
                "ibuprofen four hundred milligrams three times a day with food"
            ),
            Support::Unverified
        );
    }

    #[test]
    fn invented_number_is_unverified() {
        assert_eq!(
            judge("Temp 38.9.", "your temperature is 37.4"),
            Support::Unverified
        );
    }

    #[test]
    fn invented_drug_is_unverified() {
        assert_eq!(
            judge("Started amoxicillin 500mg.", "rest and plenty of fluids"),
            Support::Unverified
        );
    }

    #[test]
    fn paraphrase_without_figures_is_supported() {
        assert_eq!(
            judge(
                "Sore throat for four days, pain on swallowing.",
                "I've had a sore throat for about four days now and it really hurts when I swallow"
            ),
            Support::Supported
        );
    }

    #[test]
    fn no_evidence_is_unverified() {
        assert_eq!(judge("Anything at all.", ""), Support::Unverified);
    }
}
