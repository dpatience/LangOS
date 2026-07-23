# Training LangOS Models

How to build `lexicon.json` and `intent.json` for each language.

## Do you need to train when installing a language?

| What you install | Needs training? | What works without it |
|------------------|-----------------|------------------------|
| **Language pack** (`packs/de/`) | No — works immediately | Rule engine (regex patterns), grammar, express templates |
| **Statistical model** (`models/de/intent.json`) | Yes — one-time train | Free-form intent classification beyond fixed patterns |
| **Neural model** (future ONNX) | Yes — separate pipeline | Long/ambiguous text (not shipped yet — neural engine is still bootstrap) |

```bash
mix patience install language de    # loads pack — rules + templates work now
mix patience train --lang de        # builds models/de/intent.json + packs/de/lexicon.json
```

**Rule-based understanding works without training.** Training makes the **stat engine** smarter for sentences that don't match a regex pattern.

---

## Train all current languages

From the repo root:

```bash
# Option A — via CLI
mix patience train --all

# Option B — Python directly
PYTHONPATH=python/langos_train python3 -m langos_train.build_pack --all
```

This trains:

| Language | Code | Pack | Output |
|----------|------|------|--------|
| English | `en` | `packs/en/` (rich seed data) | `packs/en/lexicon.json`, `models/en/intent.json` |
| French | `fr` | `packs/fr/` | `packs/fr/lexicon.json`, `models/fr/intent.json` |
| German | `de` | `packs/de/` | `packs/de/lexicon.json`, `models/de/intent.json` |
| Turkish | `tr` | `packs/tr/` | `packs/tr/lexicon.json`, `models/tr/intent.json` |
| Kinyarwanda | `rw` | `packs/rw/` | `packs/rw/lexicon.json`, `models/rw/intent.json` |

Train one language:

```bash
mix patience train --lang fr
```

English uses `seed_en.py` (synonyms + templates). Other languages use **pack data**:

- `packs/<lang>/patterns/commands.json` — verb_map, pronoun_map
- `packs/<lang>/tests/golden.jsonl` — labeled examples

---

## First-run setup (pick default language)

```bash
mix patience setup
# or non-interactive:
mix patience setup --lang fr
```

This:

1. Sets default language in `config/langos.json`
2. Installs the language pack
3. Trains the statistical model if missing

---

## System install (production binary)

```bash
MIX_ENV=prod mix release patience
sudo ./scripts/install.sh
```

The install script copies the `patience` binary and runs `patience setup` to ask which language to start with.

Remote pack download (`patience install language de` from the internet) is planned — today packs ship in the repository or are copied to `packs/`.

---

## Neural networks (future)

The **neural engine** is still a bootstrap heuristic. Real ONNX/vLLM models will live under:

```
models/<lang>/parse.onnx
models/<lang>/express.onnx
```

That is a separate training pipeline (PyTorch → export → deploy), not the Naive Bayes `intent.json` trainer above.

See [MODEL_vs_PACK.md](./MODEL_vs_PACK.md) for the difference between packs and models.
