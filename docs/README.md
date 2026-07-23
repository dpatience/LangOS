# LangOS Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | All engineers | Semantic IR v1.2, engines, APIs, integration, development phases |
| [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) | DevOps / backend | Config, deployment, scaling, CI/CD, native dev (no Docker required) |
| [TRAINING.md](./TRAINING.md) | ML / language engineers | `mix patience train`, lexicon + intent models per language |
| [MODEL_vs_PACK.md](./MODEL_vs_PACK.md) | All engineers | Difference between `packs/` and `models/` |
| [LANGUAGE_PACK_GUIDE.md](./LANGUAGE_PACK_GUIDE.md) | Language contributors | How to create a new language pack |
| [ENGINE_SPEC.md](./ENGINE_SPEC.md) | Engine developers | Rule, Lexical, Syntax, Stat, Neural engine contracts |
| [EVOLUTION.md](./EVOLUTION.md) | Product / long-term | Language Observatory, pack tiers, 100+ language strategy |

## Quick links

- **Run LangOS:** `mix patience serve` — see [README](../README.md)
- **Train models:** `mix patience train --all` — see [TRAINING.md](./TRAINING.md)
- **Add a language:** [LANGUAGE_PACK_GUIDE.md](./LANGUAGE_PACK_GUIDE.md)
- **Config:** `config/langos.json`
- **IR schema:** `schemas/semantic_ir.v1.2.json`
- **Vocabulary IDs:** `schemas/semantic_vocabulary.json` (437 primitives)

## Current status (Phase 3.6 complete)

- 5 languages: `en`, `fr`, `de`, `tr`, `rw`
- 5 inference engines: rule, lexical, syntax, stat, neural
- Transports: HTTP, gRPC, MCP, CLI
- Compatibility: OpenAI `/v1/chat/completions`, Anthropic `/v1/messages`
- Phase 4 next: owned ONNX neural models
