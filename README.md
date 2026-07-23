# LangOS

**Language Operating System** — self-contained language infrastructure that translates between human language and structured meaning, sitting between people and intelligent applications.

LangOS understands human text and expresses structured meaning back as natural language, using **LangOS-owned engines and models**—not external language APIs.

```
Human Language  ⇄  LangOS  ⇄  Application / Reasoning AI
```

Applications like Duselang can switch from OpenAI/Anthropic to LangOS by changing `base_url` and API key only.

## Quick start

```bash
# Prerequisites: Elixir 1.16+, Rust stable, Python 3.11+ (for training)

mix deps.get
mix compile
mix test

# First-run setup (pick default language, train if needed)
mix patience setup --lang en

# CLI
mix patience understand --text "Register Clarissa in Biology A1."
mix patience express --template missing_fields --data '{"entity":"Clarissa","fields":"age, language"}'
mix patience serve     # HTTP API on http://127.0.0.1:9473

# Train statistical models for all shipped languages (optional)
mix patience train --all

# API example
curl -s http://127.0.0.1:9473/v1/understand \
  -H 'content-type: application/json' \
  -d '{"text":"Add Alice to Biology A1.","locale":"en"}' | jq .
```

Configuration: `config/langos.json` (default), `config/dev.json` (development). Set `LANGOS_CONFIG` to override.

## CLI reference

`mix langos` and `mix patience` are the same CLI.

| Command | Description |
|---------|-------------|
| `patience understand --text "..."` | Parse one sentence |
| `patience understand --file doc.txt` | Document mode (streaming pipeline) |
| `patience express --template missing_fields --data '{...}'` | Generate natural language |
| `patience serve` | Start HTTP (+ gRPC on 9474) |
| `patience install language de` | Hot-load a language pack |
| `patience train --all` | Build lexicon + intent models |
| `patience train --lang fr` | Train one language |
| `patience setup [--lang en]` | First-run: default language + train |
| `patience languages list` | Installed packs |
| `patience engines list` | Inference engines |
| `patience plugins list` | Vocabulary plugins |
| `patience benchmark [--file bench/corpus.jsonl]` | Accuracy + latency report |
| `patience mcp` | MCP server over stdio |
| `patience version` | Semantic IR version |

Production binary:

```bash
MIX_ENV=prod mix release patience
_build/prod/rel/patience/bin/patience serve
# or: sudo ./scripts/install.sh  (after release build)
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](./docs/ARCHITECTURE.md) | System design, Semantic IR v1.2, engines, APIs, phases |
| [Infrastructure](./docs/INFRASTRUCTURE.md) | Build, deploy, config, scaling, CI/CD |
| [Training](./docs/TRAINING.md) | Build `lexicon.json` + `intent.json` per language |
| [Models vs Packs](./docs/MODEL_vs_PACK.md) | `packs/` vs `models/` explained |
| [Language Pack Guide](./docs/LANGUAGE_PACK_GUIDE.md) | How to add a new language |
| [Engine Spec](./docs/ENGINE_SPEC.md) | Inference engine behaviour contract |
| [Evolution](./docs/EVOLUTION.md) | Long-term growth strategy |
| [Docs index](./docs/README.md) | Full documentation map |

## Repository layout

```
apps/langos/          Elixir runtime (API, pipeline, 5 engines)
crates/               Rust tokenizer, parser, graph, NIF
packs/                Language packs: en, fr, de, tr, rw
models/               Trained intent models per language
plugins/              Vocabulary plugins (e.g. education-vocab)
python/langos_train/  Offline training (lexicon + Naive Bayes)
python/langos_eval/   Golden test runner
sdk/elixir/           Elixir HTTP client
sdk/rust/             Rust HTTP client
schemas/              IR v1.2, vocabulary, OpenAPI, gRPC proto
config/               Runtime JSON config
scripts/install.sh    System-wide install helper
```

## APIs

**Native:**

| Endpoint | Description |
|----------|-------------|
| `POST /v1/understand` | Human text → Semantic IR |
| `POST /v1/understand/document` | Long text → merged IR |
| `POST /v1/understand/stream` | SSE streaming units |
| `POST /v1/express` | Structured data → natural language |
| `POST /v1/translate` | Cross-locale via IR |
| `GET /v1/health` | Service health |
| `GET /v1/languages` | Installed language packs |
| `GET /v1/engines` | Inference engines |

**Compatibility (drop-in migration):**

| Endpoint | Description |
|----------|-------------|
| `POST /v1/chat/completions` | OpenAI-compatible |
| `POST /v1/messages` | Anthropic-compatible |

gRPC: port **9474** (`schemas/langos.proto`). MCP: `patience mcp`.

## Stack

- **Elixir/OTP** — runtime, API, orchestration
- **Rust** — tokenization, parsing, graph NIFs
- **Python** — offline training only

Local development is **native** (no Docker required). Docker is for production.

## Shipped languages

| Code | Language | Pack | Trained model |
|------|----------|------|---------------|
| `en` | English | ✓ | ✓ (361 classes, 41k examples) |
| `fr` | French | ✓ | ✓ |
| `de` | German | ✓ | ✓ |
| `tr` | Turkish | ✓ | ✓ |
| `rw` | Kinyarwanda | ✓ | ✓ |

Rule engine + syntax parser work without training. Statistical models improve free-form understanding.

## Development status

| Phase | Status |
|-------|--------|
| 0 — Specification | ✓ complete |
| 1 — Minimal runtime (MVP) | ✓ complete |
| 2 — Multilingual + trained understanding | ✓ complete |
| 2.5 — Structural syntax engine | ✓ complete |
| 3 — Platform (MCP, gRPC, streaming, plugins) | ✓ complete |
| 3.5 — Turkish + German + expanded packs | ✓ complete |
| 3.6 — Multi-language training pipeline | ✓ complete |
| 4 — Owned neural models (ONNX) | in progress |

See [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) §12 for full phase details.

## License

See [LICENSE](./LICENSE).
