use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatternRule {
    pub id: String,
    pub pattern: String,
    pub vocab_id: String,
    pub symbol: String,
    #[serde(default = "default_unit_type")]
    pub unit_type: String,
    pub groups: Vec<GroupMapping>,
}

fn default_unit_type() -> String { "command".to_string() }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMapping {
    pub index: usize,
    pub role: String,
    #[serde(default = "default_kind")]
    pub kind: String,
}

fn default_kind() -> String { "named".to_string() }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParseMatch {
    pub rule_id: String,
    pub vocab_id: String,
    pub symbol: String,
    pub unit_type: String,
    pub arguments: Vec<Value>,
    pub span: (usize, usize),
    pub confidence: f64,
}

pub fn parse_with_patterns(text: &str, rules: &[PatternRule]) -> Option<ParseMatch> {
    let normalized = text.trim().trim_end_matches('.');
    if normalized.is_empty() {
        return None;
    }

    for rule in rules {
        let re = Regex::new(&format!("(?i)^{}$", rule.pattern)).ok()?;
        if let Some(caps) = re.captures(normalized) {
            let arguments: Vec<Value> = rule.groups.iter().filter_map(|g| {
                caps.get(g.index).map(|m| {
                    json!({
                        "role": g.role,
                        "kind": g.kind,
                        "label": m.as_str().trim(),
                        "span": [m.start(), m.end()]
                    })
                })
            }).collect();

            if arguments.is_empty() && caps.len() > 1 {
                continue;
            }

            return Some(ParseMatch {
                rule_id: rule.id.clone(),
                vocab_id: rule.vocab_id.clone(),
                symbol: rule.symbol.clone(),
                unit_type: rule.unit_type.clone(),
                arguments,
                span: (0, normalized.len()),
                confidence: 0.97,
            });
        }
    }

    None
}

pub fn load_rules_from_json(json: &str) -> Result<Vec<PatternRule>, String> {
    let doc: Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
    let patterns = doc.get("patterns").and_then(|p| p.as_array())
        .ok_or_else(|| "missing patterns array".to_string())?;

    patterns.iter().map(|p| {
        let groups: Vec<GroupMapping> = p.get("groups").and_then(|g| g.as_array())
            .map(|arr| arr.iter().filter_map(|item| {
                Some(GroupMapping {
                    index: item.get("index")?.as_u64()? as usize,
                    role: item.get("role")?.as_str()?.to_string(),
                    kind: item.get("kind").and_then(|t| t.as_str()).unwrap_or("named").to_string(),
                })
            }).collect()).unwrap_or_default();

        let id = p.get("id").and_then(|v| v.as_str())
            .ok_or_else(|| "pattern missing id".to_string())?;
        let pattern = p.get("pattern").and_then(|v| v.as_str())
            .ok_or_else(|| format!("pattern {id} missing regex"))?;
        let vocab_id = p.get("vocab_id").and_then(|v| v.as_str())
            .ok_or_else(|| format!("pattern {id} missing vocab_id"))?;
        let symbol = p.get("symbol").and_then(|v| v.as_str())
            .ok_or_else(|| format!("pattern {id} missing symbol"))?;
        let unit_type = p.get("unit_type").and_then(|v| v.as_str())
            .unwrap_or("command").to_string();

        Ok(PatternRule {
            id: id.to_string(),
            pattern: pattern.to_string(),
            vocab_id: vocab_id.to_string(),
            symbol: symbol.to_string(),
            unit_type,
            groups,
        })
    }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_with_vocab_id_and_per_arg_spans() {
        let rules = vec![PatternRule {
            id: "register".into(),
            pattern: r"register\s+(.+?)\s+in\s+(.+)".into(),
            vocab_id: "ACT_000005".into(),
            symbol: "ACTION_REGISTER".into(),
            unit_type: "command".into(),
            groups: vec![
                GroupMapping { index: 1, role: "patient".into(), kind: "named".into() },
                GroupMapping { index: 2, role: "container".into(), kind: "named".into() },
            ],
        }];

        let m = parse_with_patterns("Register Clarissa in Biology A1", &rules).unwrap();
        assert_eq!(m.vocab_id, "ACT_000005");
        assert_eq!(m.symbol, "ACTION_REGISTER");
        assert_eq!(m.arguments[0]["span"][0], 9);
        assert_eq!(m.arguments[0]["span"][1], 17);
        assert_eq!(m.arguments[0]["label"], "Clarissa");
    }
}
