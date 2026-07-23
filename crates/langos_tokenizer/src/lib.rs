use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Token {
    pub text: String,
    pub start: usize,
    pub end: usize,
    pub kind: String,
}

pub fn tokenize(text: &str) -> Vec<Token> {
    let re = Regex::new(r"[A-Za-z0-9']+|[^\sA-Za-z0-9']").expect("valid token regex");
    re.find_iter(text)
        .map(|m| Token {
            text: m.as_str().to_string(),
            start: m.start(),
            end: m.end(),
            kind: classify_token(m.as_str()),
        })
        .collect()
}

fn classify_token(token: &str) -> String {
    if token.chars().all(|c| c.is_ascii_alphabetic()) {
        "word".into()
    } else if token.chars().all(|c| c.is_ascii_digit()) {
        "number".into()
    } else {
        "punct".into()
    }
}

pub fn count_tokens(text: &str) -> usize {
    if text.trim().is_empty() {
        0
    } else {
        text.split_whitespace().count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenizes_words_and_punctuation() {
        let tokens = tokenize("Register Clarissa in Biology A1.");
        assert!(tokens.len() >= 5);
        assert_eq!(tokens[0].text, "Register");
        assert_eq!(tokens[0].kind, "word");
    }

    #[test]
    fn counts_whitespace_tokens() {
        assert_eq!(count_tokens("Add Clarissa to Biology A1"), 5);
    }
}
