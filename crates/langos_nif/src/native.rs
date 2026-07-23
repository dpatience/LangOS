use langos_graph::{build_ir_from_parse, ConfidenceDetail};
use langos_parser::{load_rules_from_json, parse_with_patterns};
use langos_tokenizer::{count_tokens as count_whitespace_tokens, tokenize as tokenize_text};
use rustler::{Env, NifResult, Term};
use serde_json::{json, Value};

#[rustler::nif]
fn tokenize(text: String) -> NifResult<String> {
    let tokens: Vec<Value> = tokenize_text(&text).into_iter().map(|t| {
        json!({"text": t.text, "start": t.start, "end": t.end, "kind": t.kind})
    }).collect();
    Ok(serde_json::to_string(&tokens).map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?)
}

#[rustler::nif]
fn count_tokens(text: String) -> NifResult<usize> {
    Ok(count_whitespace_tokens(&text))
}

#[rustler::nif]
fn parse_patterns(text: String, rules_json: String) -> NifResult<String> {
    let rules = load_rules_from_json(&rules_json)
        .map_err(|e| rustler::Error::Term(Box::new(e)))?;

    match parse_with_patterns(&text, &rules) {
        Some(m) => {
            let out = json!({
                "rule_id": m.rule_id,
                "vocab_id": m.vocab_id,
                "symbol": m.symbol,
                "unit_type": m.unit_type,
                "arguments": m.arguments,
                "span": [m.span.0, m.span.1],
                "confidence": m.confidence
            });
            Ok(serde_json::to_string(&out).unwrap())
        }
        None => Ok("null".to_string()),
    }
}

#[rustler::nif]
fn build_ir(
    language: String,
    text: String,
    vocab_id: String,
    symbol: String,
    unit_type: String,
    arguments_json: String,
    confidence_json: String,
    engine_json: String,
) -> NifResult<String> {
    let arguments: Vec<Value> = serde_json::from_str(&arguments_json)
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;

    let conf: Value = serde_json::from_str(&confidence_json)
        .unwrap_or_else(|_| json!({"overall": 0.5, "predicate": 0.5, "roles": 0.5, "references": 1.0}));
    let confidence = ConfidenceDetail {
        overall: conf["overall"].as_f64().unwrap_or(0.5),
        predicate: conf["predicate"].as_f64().unwrap_or(0.5),
        roles: conf["roles"].as_f64().unwrap_or(0.5),
        references: conf["references"].as_f64().unwrap_or(1.0),
    };

    let engine: Value = serde_json::from_str(&engine_json)
        .unwrap_or_else(|_| json!({"parser": "unknown"}));

    let ir = build_ir_from_parse(&language, &text, &vocab_id, &symbol, &unit_type, &arguments, confidence, &engine);
    Ok(serde_json::to_string(&ir).map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?)
}

#[rustler::nif]
fn detect_language(text: String, locale_hint: Option<String>) -> NifResult<String> {
    Ok(detect_language_heuristic(&text, locale_hint.as_deref()))
}

fn detect_language_heuristic(text: &str, locale_hint: Option<&str>) -> String {
    if let Some(locale) = locale_hint {
        return locale.split('-').next().unwrap_or("en").to_string();
    }
    let lower = text.to_lowercase();
    if lower.contains(" muri ") || lower.starts_with("ongeramo") || lower.contains("murakoze") {
        "rw".into()
    } else if lower.contains(" ajoutez ") || lower.contains(" bonjour ") || lower.contains(" inscrire") {
        "fr".into()
    } else {
        "en".into()
    }
}

#[allow(dead_code)]
fn load(_env: Env, _info: Term) -> bool { true }
