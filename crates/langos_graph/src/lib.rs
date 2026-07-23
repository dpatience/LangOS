use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};

fn deterministic_id(seed: &str, prefix: &str) -> String {
    let mut hasher = DefaultHasher::new();
    seed.hash(&mut hasher);
    prefix.hash(&mut hasher);
    format!("{}_{:016x}", prefix, hasher.finish())
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum NodeType {
    Predicate,
    Concept,
    Reference,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PredicateData {
    pub vocab_id: String,
    pub symbol: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConceptData {
    pub canonical: String,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReferenceData {
    pub ref_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphNode {
    pub id: String,
    pub node_type: NodeType,
    pub predicate: Option<PredicateData>,
    pub concept: Option<ConceptData>,
    pub reference: Option<ReferenceData>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphEdge {
    pub from: String,
    pub to: String,
    pub role: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mention {
    pub node_id: String,
    pub surface: String,
    pub span: (usize, usize),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfidenceDetail {
    pub overall: f64,
    pub predicate: f64,
    pub roles: f64,
    pub references: f64,
}

impl Default for ConfidenceDetail {
    fn default() -> Self {
        Self { overall: 0.5, predicate: 0.5, roles: 0.5, references: 1.0 }
    }
}

#[derive(Debug)]
pub struct SemanticGraph {
    nodes: HashMap<String, GraphNode>,
    edges: Vec<GraphEdge>,
    mentions: Vec<Mention>,
}

impl Default for SemanticGraph {
    fn default() -> Self { Self::new() }
}

impl SemanticGraph {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            edges: Vec::new(),
            mentions: Vec::new(),
        }
    }

    pub fn add_predicate_node(&mut self, vocab_id: &str, symbol: &str) -> String {
        let id = deterministic_id(&format!("pred:{}:{}", vocab_id, symbol), "p");
        if !self.nodes.contains_key(&id) {
            self.nodes.insert(id.clone(), GraphNode {
                id: id.clone(),
                node_type: NodeType::Predicate,
                predicate: Some(PredicateData {
                    vocab_id: vocab_id.to_string(),
                    symbol: symbol.to_string(),
                }),
                concept: None,
                reference: None,
            });
        }
        id
    }

    pub fn add_concept_node(&mut self, canonical: &str, kind: &str) -> String {
        let id = deterministic_id(&format!("concept:{}:{}", canonical, kind), "c");
        if !self.nodes.contains_key(&id) {
            self.nodes.insert(id.clone(), GraphNode {
                id: id.clone(),
                node_type: NodeType::Concept,
                predicate: None,
                concept: Some(ConceptData {
                    canonical: canonical.to_string(),
                    kind: kind.to_string(),
                }),
                reference: None,
            });
        }
        id
    }

    pub fn add_reference_node(&mut self, ref_type: &str) -> String {
        let id = deterministic_id(&format!("ref:{}", ref_type), "r");
        if !self.nodes.contains_key(&id) {
            self.nodes.insert(id.clone(), GraphNode {
                id: id.clone(),
                node_type: NodeType::Reference,
                predicate: None,
                concept: None,
                reference: Some(ReferenceData {
                    ref_type: ref_type.to_string(),
                }),
            });
        }
        id
    }

    pub fn add_edge(&mut self, from: &str, to: &str, role: &str) {
        self.edges.push(GraphEdge {
            from: from.to_string(),
            to: to.to_string(),
            role: role.to_string(),
        });
    }

    pub fn add_mention(&mut self, node_id: &str, surface: &str, span: (usize, usize)) {
        self.mentions.push(Mention {
            node_id: node_id.to_string(),
            surface: surface.to_string(),
            span,
        });
    }

    pub fn to_ir(
        &self,
        language: &str,
        text: &str,
        utterance_type: &str,
        confidence: &ConfidenceDetail,
        engine: &Value,
    ) -> Value {
        let nodes: Vec<Value> = self.nodes.values().map(|n| {
            let mut obj = json!({"id": n.id, "type": match n.node_type {
                NodeType::Predicate => "predicate",
                NodeType::Concept => "concept",
                NodeType::Reference => "reference",
            }});
            if let Some(ref p) = n.predicate {
                obj["predicate"] = json!({"id": p.vocab_id, "symbol": p.symbol});
            }
            if let Some(ref c) = n.concept {
                obj["concept"] = json!({"canonical": c.canonical, "kind": c.kind});
            }
            if let Some(ref r) = n.reference {
                obj["reference"] = json!({"ref": r.ref_type});
            }
            obj
        }).collect();

        let edges: Vec<Value> = self.edges.iter().map(|e| {
            json!({"from": e.from, "to": e.to, "role": e.role})
        }).collect();

        let mentions: Vec<Value> = self.mentions.iter().map(|m| {
            json!({"node_id": m.node_id, "surface": m.surface, "span": [m.span.0, m.span.1]})
        }).collect();

        json!({
            "version": "1.2",
            "source": {"language": language, "text": text},
            "graph": {"nodes": nodes, "edges": edges},
            "mentions": mentions,
            "utterance_type": utterance_type,
            "confidence": {
                "overall": confidence.overall,
                "predicate": confidence.predicate,
                "roles": confidence.roles,
                "references": confidence.references
            },
            "meta": {
                "detected_language": language,
                "engine": engine
            }
        })
    }
}

pub fn build_ir_from_parse(
    language: &str,
    text: &str,
    vocab_id: &str,
    symbol: &str,
    utterance_type: &str,
    arguments: &[Value],
    confidence: ConfidenceDetail,
    engine: &Value,
) -> Value {
    let mut graph = SemanticGraph::new();

    let pred_node_id = graph.add_predicate_node(vocab_id, symbol);

    for arg in arguments {
        let role = arg.get("role").and_then(|v| v.as_str()).unwrap_or("theme");
        let surface = arg.get("label").or_else(|| arg.get("surface"))
            .and_then(|v| v.as_str()).unwrap_or("");
        let kind = arg.get("kind").and_then(|v| v.as_str()).unwrap_or("named");
        let ref_id = arg.get("ref").and_then(|v| v.as_str());

        let span_start = arg.get("span").and_then(|s| s.get(0)).and_then(|v| v.as_u64()).unwrap_or(0) as usize;
        let span_end = arg.get("span").and_then(|s| s.get(1)).and_then(|v| v.as_u64()).unwrap_or(0) as usize;

        let node_id = if let Some(r) = ref_id {
            graph.add_reference_node(r)
        } else {
            graph.add_concept_node(&surface.to_lowercase(), kind)
        };

        graph.add_edge(&pred_node_id, &node_id, role);
        graph.add_mention(&node_id, surface, (span_start, span_end));
    }

    graph.to_ir(language, text, utterance_type, &confidence, engine)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn builds_graph_based_ir() {
        let engine = json!({"parser": "rule", "language_pack": "en", "version": "1.0.0"});
        let confidence = ConfidenceDetail { overall: 0.97, predicate: 0.99, roles: 0.95, references: 1.0 };

        let ir = build_ir_from_parse(
            "en",
            "Register Clarissa in Biology A1",
            "ACT_000005",
            "ACTION_REGISTER",
            "command",
            &[
                json!({"role": "patient", "label": "Clarissa", "kind": "named", "span": [9, 17]}),
                json!({"role": "container", "label": "Biology A1", "kind": "named", "span": [21, 31]}),
            ],
            confidence,
            &engine,
        );

        assert_eq!(ir["version"], "1.2");
        assert_eq!(ir["utterance_type"], "command");

        let nodes = ir["graph"]["nodes"].as_array().unwrap();
        let edges = ir["graph"]["edges"].as_array().unwrap();
        let mentions = ir["mentions"].as_array().unwrap();

        assert_eq!(nodes.len(), 3);
        assert_eq!(edges.len(), 2);
        assert_eq!(mentions.len(), 2);

        let pred_node = nodes.iter().find(|n| n["type"] == "predicate").unwrap();
        assert_eq!(pred_node["predicate"]["id"], "ACT_000005");
        assert_eq!(pred_node["predicate"]["symbol"], "ACTION_REGISTER");

        let patient_edge = edges.iter().find(|e| e["role"] == "patient").unwrap();
        assert_eq!(patient_edge["from"], pred_node["id"]);

        let clarissa_mention = mentions.iter().find(|m| m["surface"] == "Clarissa").unwrap();
        assert_eq!(clarissa_mention["span"], json!([9, 17]));
    }

    #[test]
    fn builds_question_with_references() {
        let engine = json!({"parser": "neural_bootstrap", "language_pack": "en", "version": "1.0.0"});
        let confidence = ConfidenceDetail { overall: 0.70, predicate: 0.75, roles: 0.70, references: 1.0 };

        let ir = build_ir_from_parse(
            "en",
            "Do you know me?",
            "QRY_000001",
            "QUERY_KNOW",
            "question",
            &[
                json!({"role": "experiencer", "label": "you", "kind": "pronoun", "ref": "REF_LISTENER", "span": [3, 6]}),
                json!({"role": "theme", "label": "me", "kind": "pronoun", "ref": "REF_SPEAKER", "span": [12, 14]}),
            ],
            confidence,
            &engine,
        );

        let nodes = ir["graph"]["nodes"].as_array().unwrap();
        let ref_nodes: Vec<&Value> = nodes.iter().filter(|n| n["type"] == "reference").collect();
        assert_eq!(ref_nodes.len(), 2);

        let listener = ref_nodes.iter().find(|n| n["reference"]["ref"] == "REF_LISTENER").unwrap();
        assert!(listener["id"].as_str().unwrap().starts_with("r_"));
    }
}
