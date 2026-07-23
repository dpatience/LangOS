# LangOS Engine Behaviour Specification

**Version:** 1.0  
**Status:** Phase 0 deliverable  
**Related:** [ARCHITECTURE.md](./ARCHITECTURE.md)

---

## 1. Purpose

This document defines the **behaviour contract** for LangOS inference engines. All engines are LangOS-owned; no engine may delegate to external language APIs.

---

## 2. Engine Types

| ID | Type | Technology | Typical latency |
|----|------|------------|-----------------|
| `rule` | RuleEngine | Rust regex/CFG, language pack patterns | 1–5 ms |
| `stat` | StatEngine | Small ONNX models (LangOS-trained) | 5–20 ms |
| `neural` | NeuralEngine | LangOS models via ONNX / bootstrap heuristics | 10–500 ms |

---

## 3. Elixir Behaviour

```elixir
defmodule LangOS.Engine do
  @type semantic_ir :: map()
  @type text :: String.t()
  @type tokens :: list()
  @type parse_tree :: map()
  @type opts :: keyword()

  @callback tokenize(text(), opts()) :: {:ok, tokens()} | {:error, term()}
  @callback parse(tokens(), opts()) :: {:ok, parse_tree()} | {:error, term()}
  @callback extract_meaning(parse_tree(), opts()) :: {:ok, semantic_ir()} | {:error, term()}
  @callback generate(semantic_ir(), opts()) :: {:ok, text()} | {:error, term()}

  @callback capabilities() :: [atom()]
  @callback health() :: :ok | {:error, term()}
end
```

### 3.1 Capabilities Atoms

| Atom | Meaning |
|------|---------|
| `:tokenize` | Can segment text into tokens |
| `:parse` | Can produce syntactic/semantic parse structure |
| `:extract` | Can produce Semantic IR from parse tree |
| `:generate` | Can produce natural language from IR or template data |
| `:detect_language` | Can detect input language |
| `:coreference` | Can mark reference slots |

### 3.2 Health

- `:ok` — engine ready
- `{:error, reason}` — engine unavailable; router may fall back within LangOS

---

## 4. Stage Mapping

| Pipeline stage | Primary engine | Fallback |
|----------------|----------------|----------|
| Language detection | `stat` | `rule` (locale hint) |
| Simple commands | `rule` | `stat` |
| Ambiguous parse | `neural` | `stat` → `rule` |
| Entity extraction | `stat` | `rule` |
| Coreference | `neural` | none (skip with low confidence) |
| Generation | `neural` | `rule` (templates) |

---

## 5. Router Contract

```elixir
LangOS.Router.select_engine(stage, %{text: text, locale: locale, token_count: n})
# => {:ok, engine_id} | {:error, :no_engine}
```

Routing rules (Phase 1):

- `token_count <= 12` and command-like → `rule`
- otherwise → `neural` if enabled, else `rule`
- on `{:error, _}` from selected engine → next fallback in chain

**Never** route to an external API.

---

## 6. Engine Registry

```elixir
LangOS.Engine.Registry.list/0
# => [%{id: "rule", capabilities: [...], health: :ok}, ...]

LangOS.Engine.Registry.get/1
# => {:ok, module} | {:error, :not_found}
```

Engines register at application startup from config (`config/langos.yaml`).

---

## 7. Output Validation

All engines that produce Semantic IR **must** pass output through `LangOS.IR.validate/1` before returning to the pipeline.

Invalid IR → `{:error, {:invalid_ir, errors}}` — not forwarded to clients.

---

## 8. Phase 1 Implementations

| Module | ID | Capabilities | Notes |
|--------|----|--------------|-------|
| `LangOS.Engine.Rule` | `rule` | tokenize, parse, extract, generate, detect_language | English pack patterns |
| `LangOS.Engine.Neural` | `neural` | parse, extract, generate | Bootstrap heuristics until models ship |
| `LangOS.Engine.Stat` | `stat` | detect_language | Stub in Phase 1; locale hint fallback |

---

## 9. NIF Boundary (Rust)

Rust NIFs expose:

- `LangOS.Native.tokenize/2`
- `LangOS.Native.parse/2`
- `LangOS.Native.build_graph/1`
- `LangOS.Native.merge_graphs/1`

NIFs return JSON strings or maps; Elixir engines decode and validate.

Dirty NIF scheduling required for inference-heavy calls.

---

## 10. Versioning

Engine behaviour spec version tracks kernel releases. Adding optional callbacks requires a minor bump; breaking callback changes require major bump and coordinated release.
