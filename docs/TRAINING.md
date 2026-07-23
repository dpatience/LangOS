# Training LangOS Models

How to build `lexicon.json` and `intent.json` for each language.

## Do you need to train when installing a language?

| Step | Needs training? | What works without it |
|------|-----------------|------------------------|
| `patience install language de` | No | Rule engine, syntax parser, grammar, express templates |
| `patience train --lang de` | Yes (one-time) | Stat engine for free-form intent classification |

**Rule + syntax understanding works immediately after install.** Training improves sentences that don't match a regex pattern.

---

## Train all shipped languages

```bash
mix patience train --all
```

| Language | Code | Lexicon entries | Intent classes | Examples |
|----------|------|-----------------|----------------|----------|
| English | `en` | 5,718 | 361 | 41,577 |
| French | `fr` | 114 | 28 | 318 |
| German | `de` | 163 | 42 | 552 |
| Turkish | `tr` | 376 | 217 | 1,987 |
| Kinyarwanda | `rw` | 489 | 178 | 2,710 |

Train one language:

```bash
mix patience train --lang fr
```

Python equivalent:

```bash
PYTHONPATH=python/langos_train python3 -m langos_train.build_pack --all
PYTHONPATH=python/langos_train python3 -m langos_train.build_pack --lang de
```

---

## What gets built

```
packs/<lang>/lexicon.json    ← word/phrase → vocabulary ID (used by Lexical engine)
models/<lang>/intent.json    ← Naive Bayes intent classifier (used by Stat engine)
```

English uses rich seed data (`python/langos_train/seed_en.py`). Other languages train from:

- `packs/<lang>/patterns/commands.json` — verb_map, pronoun_map
- `packs/<lang>/tests/golden.jsonl` — labeled utterances

---

## First-run setup

```bash
mix patience setup              # interactive language picker
mix patience setup --lang fr    # non-interactive
```

This sets the default language in `config/langos.json`, installs the pack, and trains the model if missing.

---

## Install + train workflow

```bash
# 1. Load pack (rules + syntax + templates — works now)
mix patience install language de

# 2. Train statistical model (optional, ~seconds)
mix patience train --lang de

# 3. Verify
mix patience understand --text "Registriere Alice in Biologie A1." --locale de
```

---

## System install

```bash
MIX_ENV=prod mix release patience
sudo ./scripts/install.sh
patience setup --lang en
patience serve
```

Remote pack download from the internet is **planned** — today packs ship in the repository.

---

## Neural networks (Phase 4)

The **neural engine** is still bootstrap heuristics. Real ONNX models will live under `models/<lang>/parse.onnx` — a separate PyTorch → export pipeline, not the Naive Bayes trainer above.

See [MODEL_vs_PACK.md](./MODEL_vs_PACK.md) and [ARCHITECTURE.md](./ARCHITECTURE.md) Phase 4.
