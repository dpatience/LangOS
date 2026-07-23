//! Rust SDK for LangOS — translate human language to Semantic IR and back.
//!
//! ```no_run
//! use langos_sdk::Client;
//!
//! let client = Client::new("http://127.0.0.1:9473");
//! let resp = client.understand("Register Clarissa in Biology A1.", None).unwrap();
//! let ir = &resp["ir"];
//! assert_eq!(ir["version"], "1.2");
//! ```

use serde_json::{json, Value};

/// Errors returned by the LangOS client.
#[derive(Debug)]
pub enum Error {
    /// Transport-level failure (connection refused, timeout, ...).
    Transport(String),
    /// LangOS returned a non-success status; carries status code and body.
    Api(u16, Value),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Transport(msg) => write!(f, "transport error: {msg}"),
            Error::Api(status, body) => write!(f, "LangOS API error {status}: {body}"),
        }
    }
}

impl std::error::Error for Error {}

/// Client for the LangOS native HTTP API.
pub struct Client {
    base_url: String,
    agent: ureq::Agent,
}

impl Client {
    /// Create a client for a LangOS server, e.g. `http://127.0.0.1:9473`.
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into().trim_end_matches('/').to_string(),
            agent: ureq::Agent::new(),
        }
    }

    /// Parse text into Semantic IR v1.2. Omit `locale` for automatic
    /// language detection across installed packs.
    pub fn understand(&self, text: &str, locale: Option<&str>) -> Result<Value, Error> {
        let mut body = json!({ "text": text });
        if let Some(locale) = locale {
            body["locale"] = json!(locale);
        }
        self.post("/v1/understand", body)
    }

    /// Parse a multi-sentence document: one IR per semantic unit, with
    /// coreference slots carrying candidates from earlier units.
    pub fn understand_document(&self, text: &str, locale: Option<&str>) -> Result<Value, Error> {
        let mut body = json!({ "text": text });
        if let Some(locale) = locale {
            body["locale"] = json!(locale);
        }
        self.post("/v1/understand/document", body)
    }

    /// Generate natural language from a template and data.
    pub fn express(&self, template: &str, locale: &str, data: Value) -> Result<Value, Error> {
        self.post(
            "/v1/express",
            json!({ "template": template, "locale": locale, "data": data }),
        )
    }

    /// Translate text between locales through the Semantic IR pivot.
    pub fn translate(&self, text: &str, from: &str, to: &str) -> Result<Value, Error> {
        self.post(
            "/v1/translate",
            json!({ "text": text, "from": from, "to": to }),
        )
    }

    /// Server health.
    pub fn health(&self) -> Result<Value, Error> {
        let url = format!("{}/v1/health", self.base_url);
        match self.agent.get(&url).call() {
            Ok(resp) => resp
                .into_json()
                .map_err(|e| Error::Transport(e.to_string())),
            Err(err) => Err(map_err(err)),
        }
    }

    fn post(&self, path: &str, body: Value) -> Result<Value, Error> {
        let url = format!("{}{}", self.base_url, path);
        match self.agent.post(&url).send_json(body) {
            Ok(resp) => resp
                .into_json()
                .map_err(|e| Error::Transport(e.to_string())),
            Err(err) => Err(map_err(err)),
        }
    }
}

fn map_err(err: ureq::Error) -> Error {
    match err {
        ureq::Error::Status(status, resp) => {
            let body = resp.into_json().unwrap_or(Value::Null);
            Error::Api(status, body)
        }
        other => Error::Transport(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_url_trailing_slash_is_normalized() {
        let client = Client::new("http://127.0.0.1:9473/");
        assert_eq!(client.base_url, "http://127.0.0.1:9473");
    }

    #[test]
    fn transport_error_when_server_absent() {
        // Port 9 (discard) is never a LangOS server.
        let client = Client::new("http://127.0.0.1:9");
        match client.understand("hello", None) {
            Err(Error::Transport(_)) => {}
            other => panic!("expected transport error, got {other:?}"),
        }
    }
}
