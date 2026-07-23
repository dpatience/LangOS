# LangOS

**Language Operating System** — a self-contained language infrastructure that translates between human language and structured meaning, sitting between people and intelligent applications.

LangOS understands **anything a human can write** and expresses **anything a reasoning AI needs to say back**—using LangOS-owned models and pipelines, not external language APIs.

```
Human Language  ⇄  LangOS  ⇄  Application / Reasoning AI
```

Applications like Duselang that previously called OpenAI or Anthropic for language work can switch to LangOS by changing `base_url` and API key only—no client code changes.

## Quick start

```bash
# Prerequisites: Elixir 1.16+, Rust stable, Python 3.11+ (optional for training)

mix deps.get
mix compile          # builds Rust NIFs automatically
mix test

# CLI (mix langos or mix patience — same thing)
mix langos understand --text "Register Clarissa in Biology A1."
mix langos express --template missing_fields --data '{"entity":"Clarissa","fields":"age, language"}'
mix langos serve     # HTTP API on http://127.0.0.1:9473

# Example API call
curl -s http://127.0.0.1:9473/v1/understand \
  -H 'content-type: application/json' \
  -d '{"text":"Add Alice to Biology A1.","locale":"en"}' | jq .
```

Configuration lives in `config/dev.json` (development) and `config/langos.json` (default). Set `LANGOS_CONFIG` to override.

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](./docs/ARCHITECTURE.md) | System design, Semantic IR, inference engines, API compatibility |
| [Infrastructure](./docs/INFRASTRUCTURE.md) | Build, deploy, scale, models, caching, CI/CD |
| [Evolution](./docs/EVOLUTION.md) | Long-term growth, language packs, Observatory, post-v1.0 strategy |
| [Engine Spec](./docs/ENGINE_SPEC.md) | Inference engine behaviour contract |

## Repository layout

```
apps/langos/          Elixir runtime (API, pipeline, engines)
crates/               Rust tokenizer, parser, graph, NIF
packs/en/             English language pack (patterns, templates, golden tests)
schemas/              Semantic IR JSON Schema, OpenAPI
sdk/elixir/           Elixir HTTP client
python/               Offline training & evaluation (Phase 2+)
config/               Runtime configuration (JSON)
```

## APIs

**Native (purpose-built):**

```
POST /v1/understand   —  human text  →  Semantic IR (JSON)
POST /v1/express      —  structured data  →  natural language
POST /v1/translate    —  cross-locale via Semantic IR
GET  /v1/health       —  service health
GET  /v1/languages    —  installed language packs
GET  /v1/engines      —  installed inference engines
```

**Compatibility (Phase 2):** OpenAI `/v1/chat/completions`, Anthropic `/v1/messages`

## Stack

- **Elixir/OTP** — runtime, API, orchestration
- **Rust** — tokenization, parsing, graph, inference NIFs
- **Python** — offline training and evaluation

Local development runs **natively** (no Docker required). Docker is for production deployment and optional full-stack testing.

## Development status

- **Phase 0** — specification (schemas, engine contract, OpenAPI) ✓
- **Phase 1** — minimal runtime MVP ✓
- **Phase 2** — multilingual packs, compatibility APIs, Python/Rust SDKs

##Commands on Use
# Start server
mix langos serve
# or (same thing, after recompile)
mix patience serve

# One-off CLI (no server)
mix langos understand --text "Register Clarissa in Biology A1."
mix langos express --template missing_fields --data '{"entity":"Clarissa","fields":"age, language"}'
mix langos engines list
mix langos languages list
mix langos version

# Test API (server running in another terminal)
curl -s http://127.0.0.1:9473/v1/understand \
  -H 'content-type: application/json' \
  -d '{"text":"Add Alice to Biology A1.","locale":"en"}' | jq .

## Incase wants to test for production compatibility

MIX_ENV=prod mix release patience
_build/prod/rel/patience/bin/patience serve

## Brainstorming Notes

Design discussions are captured in [`chats/`](./chats/) (1.md – 10.md).

## License

See [LICENSE](./LICENSE).
