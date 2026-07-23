# LangOS Engine Behaviour Specification

**Version:** 1.1  
**Status:** Current  
**Related:** [ARCHITECTURE.md](./ARCHITECTURE.md) · [TRAINING.md](./TRAINING.md)

---

## 1. Purpose

Defines the **behaviour contract** for LangOS inference engines. All engines are LangOS-owned; no engine may delegate to external language APIs.

---

## 2. Engine Types (shipped)

| ID | Module | Technology | Typical latency | Role |
|----|--------|------------|-----------------|------|
| `rule` | `LangOS.Engine.Rule` | Regex patterns from language packs | 1–5 ms | High-precision command matching |
| `lexical` | `LangOS.Engine.Lexical` | Pack lexicon + vocabulary IDs | 2–10 ms | Word/phrase → vocab ID lookup |
| `syntax` | `LangOS.Engine.Syntax` | Deterministic tokenizer → parser → mapper | 5–20 ms | Structural parse with morphology |
| `stat` | `LangOS.Engine.Stat` | Naive Bayes (`models/<lang>/intent.json`) | 5–20 ms | Free-form intent classification |
| `neural` | `LangOS.Engine.Neural` | Bootstrap heuristics (ONNX future) | 10–50 ms | Last-resort fallback |

---

## 3. Elixir Behaviour

```elixir
defmodule LangOS.Engine do
  @callback tokenize(text(), opts()) :: {:ok, tokens()} | {:error, term()}
  @callback parse(text(), opts()) :: {:ok, parse_tree()} | {:error, term()}
  @callback extract_meaning(parse_tree(), opts()) :: {:ok, semantic_ir()} | {:error, term()}
  @callback generate(request(), opts()) :: {:ok, text()} | {:error, term()}
  @callback capabilities() :: [atom()]
  @callback health() :: :ok | {:error, term()}
end
```

### Capabilities

| Atom | Meaning |
|------|---------|
| `:tokenize` | Segment text into tokens |
| `:parse` | Produce parse tree |
| `:extract` | Produce Semantic IR v1.2 graph |
| `:generate` | Natural language from templates/IR |
| `:detect_language` | Detect input language |
| `:coreference` | Mark reference slots |

---

## 4. Parse Chain (current)

Configured in `config/langos.json` → `routing.stages.parse`:

```
rule → lexical → syntax → stat → neural
```

| Engine | When it wins | On failure |
|--------|--------------|------------|
| `rule` | Regex pattern matches | fall through |
| `lexical` | Lexicon identifies predicate | fall through |
| `syntax` | Deterministic structural parse | fall through |
| `stat` | Naive Bayes confidence ≥ threshold | fall through |
| `neural` | Bootstrap heuristic match | `UNKNOWN` |

**Design intent:** precise rules and syntax first; statistical/neural engines are fallbacks—not the main path.

Generation chain: `neural` (delegates to rule templates for express).

---

## 5. Stat Engine Details

- Model path: `models/<locale>/intent.json` (per-language; falls back to `en` if missing)
- Algorithm: multinomial Naive Bayes, unigram + bigram features
- Confidence: top-1 vs top-2 margin × feature hit rate
- Threshold: `engines.stat.min_confidence` (default 0.3)
- Training: `mix patience train --lang <code>` or `python3 -m langos_train.build_pack`

---

## 6. Syntax Engine Details

Deterministic pipeline per language pack:

1. Tokenize (Unicode-aware)
2. Morphological analysis (prefix/suffix stripping from pack declarations)
3. Dependency-style role assignment from vocabulary role signatures
4. Semantic graph builder → IR v1.2

Pack morphology declarations:

| Declaration | Example language |
|-------------|------------------|
| `strip_prefixes` + `subject_prefixes` | Kinyarwanda |
| `strip_suffixes` + `subject_suffixes` | Turkish |
| `word_order: "sov"` | Turkish |
| `strip_apostrophe` | Turkish |

---

## 7. Router Contract

```elixir
LangOS.Router.select_engine(stage, %{text: text, locale: locale, token_count: n})
# => {:ok, engine_id} | {:error, :no_engine}
```

Routing reads `routing.stages` from config. Fallback stays within LangOS engines—never external APIs.

---

## 8. Engine Registry

```elixir
LangOS.Engine.Registry.list/0
# => [%{id: "rule", capabilities: [...], health: "ok"}, ...]

mix patience engines list   # CLI equivalent
```

Engines register at startup from `config/*.json` → `engines.*.enabled`.

---

## 9. Output Validation

All IR output passes `LangOS.IR.validate/1` before returning to clients. Invalid IR → `{:error, {:invalid_ir, errors}}`.

---

## 10. NIF Boundary (Rust)

| NIF | Purpose |
|-----|---------|
| `LangOS.Native.tokenize/2` | Tokenization |
| `LangOS.Native.parse/2` | Syntactic parsing |
| `LangOS.Native.build_graph/1` | Graph construction |
| `LangOS.Native.merge_graphs/1` | Document merge |
| `LangOS.Native.detect_language/2` | Language detection signals |

Dirty NIF scheduling for inference-heavy calls.

---

## 11. Health Checks

| Engine | `:ok` when |
|--------|------------|
| `rule` | Pack patterns loaded |
| `lexical` | Lexicon file exists for locale |
| `syntax` | Grammar loaded |
| `stat` | `models/<locale>/intent.json` loadable |
| `neural` | Always (bootstrap) |

---

## 12. Versioning

Engine behaviour spec version tracks kernel releases. Optional callbacks = minor bump; breaking changes = major bump + coordinated release.
