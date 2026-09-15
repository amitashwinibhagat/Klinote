//! Sentence-level grounding checks.
//!
//! The strongest trust a local scribe can offer is a mechanical check: does the
//! sentence's own evidence actually contain what the sentence claims? Prose
//! overlap is a bad test — every useful note paraphrases. Three things are not
//! paraphrase, and those are what we check:
//!
//! 1. **Numbers.** `37.4`, `88`, `400mg`, `1g`, `4 days`. If a figure appears in
//!    the note and not in the words that were heard, a clinician must look.
//! 2. **Dose frequency.** `q8h` and "three times a day" are one instruction
//!    written two ways, so they have to compare equal. `q4h` and "four times a
//!    day" are **not** the same instruction — every four hours is six doses and
//!    four times a day is every six — so they must not.
//! 3. **Drug names.** A medicine in the note that nobody said is the exact
//!    failure mode that makes clinicians refuse these tools.
//!
//! A sentence with no evidence at all is unverified by definition. Everything
//! else passes. This is a review prompt, not an error: it never blocks, never
//! rewrites, and never claims the sentence is wrong.
//!
//! Why dose frequency is its own comparison rather than arithmetic on digits:
//! it used to be neither. `q8h` contributed the number 8 and "three times a day"
//! contributed 3, so a correct line was flagged; `q4h` contributed 4 and "four
//! times a day" contributed 4, so a wrong line passed. The check was matching
//! digits that happened to coincide, and the tests recorded the coincidences.

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
    let cited_doses = doses_per_day(cited);
    for doses in doses_per_day(sentence) {
        if !cited_doses.contains(&doses) {
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

/// Doses per day, however the instruction was written.
///
/// One instruction, several spellings: `q8h`, `tds` and "three times a day" all
/// mean three doses a day and must compare equal. The conversion is the point —
/// comparing the digits gives 8 against 3 for the same instruction.
pub fn doses_per_day(text: &str) -> HashSet<u64> {
    let tokens = formulary::tokens_of(text);
    let mut out = HashSet::new();

    for (index, token) in tokens.iter().enumerate() {
        if let Some(doses) = interval_as_doses(token) {
            out.insert(doses);
            continue;
        }
        if let Some(doses) = latin_frequency(token) {
            out.insert(doses);
            continue;
        }
        // "four times a day", "three times daily"
        if tokens.get(index + 1).map(String::as_str) == Some("times") {
            if let Some(value) = unit_value(token) {
                out.insert(value);
            }
        }
        if token == "twice" {
            out.insert(2);
        }
        if token == "once" {
            out.insert(1);
        }
    }

    out
}

/// `q8h`, `q12h` — a dosing *interval*, not a quantity.
///
/// Separated from [`interval_as_doses`] on purpose: `q5h` is an interval whose
/// frequency does not divide a day cleanly, so it is not a frequency we can
/// state — but it is still an interval, and reading its digits as the quantity
/// "5" would compare something nobody said.
fn is_interval(token: &str) -> bool {
    let Some(rest) = token.strip_prefix('q') else {
        return false;
    };
    let Some(hours) = rest.strip_suffix('h') else {
        return false;
    };
    !hours.is_empty() && hours.chars().all(|c| c.is_ascii_digit())
}

/// `q8h` — every eight hours — is three doses a day.
///
/// Returns `None` for an interval that does not divide a day cleanly (`q5h`):
/// that is not a frequency anybody stated, so it is not something this check
/// can hold a note to.
fn interval_as_doses(token: &str) -> Option<u64> {
    if !is_interval(token) {
        return None;
    }
    let hours: u64 = token.strip_prefix('q')?.strip_suffix('h')?.parse().ok()?;
    if hours == 0 || 24 % hours != 0 {
        return None;
    }
    Some(24 / hours)
}

/// Frequency written in Latin shorthand.
///
/// `od` is deliberately absent. It is ambiguous — once daily, or the right eye —
/// and `register.rs` already flags it for the clinician rather than reading it.
/// Guessing here would let a sentence about an eye satisfy a dosing check.
fn latin_frequency(token: &str) -> Option<u64> {
    Some(match token {
        "bd" | "bid" => 2,
        "tds" | "tid" => 3,
        "qds" | "qid" => 4,
        _ => return None,
    })
}

/// Numeric values in `text`, with spoken forms folded to digits so that
/// "thirty seven point four" and "37.4" compare equal, and "four times" and
/// "q4h" agree.
///
/// Speech recognition writes numbers as words ("eighty eight", "four hundred
/// milligrams"), while a drafted note writes digits ("88", "400mg"). Comparing
/// the two requires reading the words as numbers, not just extracting digits.
///
/// Dose intervals are the exception: `q8h` is not the quantity eight, it is a
/// frequency, and it is compared by [`doses_per_day`] instead. Counting its
/// digits here is what made an 8 sit against a spoken 3.
pub fn numbers(text: &str) -> HashSet<String> {
    let tokens = formulary::tokens_of(text);
    let mut out = HashSet::new();
    let mut index = 0;
    while index < tokens.len() {
        let token = &tokens[index];
        if token.chars().any(|c| c.is_ascii_digit()) {
            if !is_interval(token) {
                for value in digits_in(token) {
                    out.insert(value);
                }
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
        // `q6h` is four doses a day, which is what "four times a day" means —
        // `q4h` is six. This assertion used to say `q4h` and pass, because both
        // sides happened to contain a 4.
        assert_eq!(
            judge(
                "Paracetamol 1g q6h. Ibuprofen 400mg tds.",
                "paracetamol one gram four times a day and ibuprofen four hundred milligrams three times a day"
            ),
            Support::Supported
        );
    }

    /// One instruction written two ways must compare equal. This is the false
    /// positive that started it: a correct line flagged as unverified.
    #[test]
    fn an_interval_and_a_frequency_are_the_same_instruction() {
        assert_eq!(
            judge(
                "Ibuprofen 400mg q8h with food.",
                "ibuprofen four hundred milligrams three times a day with food"
            ),
            Support::Supported,
            "q8h is three doses a day"
        );
        assert_eq!(
            judge(
                "Paracetamol 1g qds.",
                "paracetamol one gram four times a day as needed"
            ),
            Support::Supported
        );
    }

    /// And the one that passed while being wrong. Every four hours is six doses
    /// a day; four times a day is every six. The digits agree and the
    /// instruction does not, which is exactly the case digits cannot see.
    #[test]
    fn a_wrong_interval_is_caught_even_when_the_digits_agree() {
        assert_eq!(
            judge(
                "Paracetamol 1g q4h.",
                "paracetamol one gram four times a day"
            ),
            Support::Unverified
        );
    }

    /// An interval that does not divide a day is not a frequency, so it is not
    /// compared as one — and its digits are not read as a quantity either.
    #[test]
    fn an_odd_interval_is_not_read_as_a_quantity() {
        assert!(!doses_per_day("q5h").contains(&0));
        assert!(doses_per_day("q5h").is_empty());
        assert!(numbers("q5h").is_empty(), "an interval is not a quantity");
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
