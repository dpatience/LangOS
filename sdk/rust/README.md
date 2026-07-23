# langos-sdk (Rust)

Rust SDK for [LangOS](../../README.md) — translate human language to
Semantic IR v1.2 and back, over the native HTTP API.

```rust
use langos_sdk::Client;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new("http://127.0.0.1:9473");

    // Single utterance — locale omitted, LangOS detects the language.
    let resp = client.understand("Can I join the class?", None)?;
    println!("{}", serde_json::to_string_pretty(&resp["ir"])?);

    // Multi-sentence document: one IR per semantic unit + coreference slots.
    let doc = client.understand_document("Register Clarissa. She starts Monday.", None)?;
    println!("units: {}", doc["unit_count"]);

    // Translate via the Semantic IR pivot.
    let out = client.translate("Register Clarissa in Biology A1.", "en", "fr")?;
    println!("{}", out["text"]);

    Ok(())
}
```

Start the server with `mix langos serve` (or `patience serve`). For gRPC
instead of HTTP, see `schemas/langos.proto` (port 9474).
