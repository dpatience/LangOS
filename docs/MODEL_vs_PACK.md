# Models vs Packs

| | `packs/` | `models/` |
|---|----------|-----------|
| **What** | Language knowledge you define | Trained artifacts (math/weights) |
| **Who creates it** | You / curators | `mix patience train` / Python |
| **Per language** | `packs/en/`, `packs/fr/`, … | `models/en/`, `models/fr/`, … |
| **Editable by hand** | Yes | No — retrain instead |
| **Runtime role** | Rules, grammar, templates, lexicon lookup | Statistical intent classification |

## `packs/` — language packs

```
packs/de/
├── manifest.json
├── grammar.json
├── patterns/commands.json
├── templates/express/
└── tests/golden.jsonl
```

Loaded by the rule engine, grammar realizer, and express path.  
Install: `mix patience install language de`

## `models/` — trained engines

```
models/de/intent.json    # Naive Bayes intent classifier
```

Built by: `mix patience train --lang de`  
Used by: stat engine (`engines.stat.model` in config)

## Flow

```
packs/<lang>/patterns/  ──┐
packs/<lang>/tests/     ──┼──► mix patience train ──► models/<lang>/intent.json
                          │                         packs/<lang>/lexicon.json
schemas/semantic_vocabulary.json
```

## When to use which

| Task | Folder / command |
|------|------------------|
| Add grammar or command patterns | `packs/<lang>/` |
| Improve intent on free-form text | `mix patience train --lang <lang>` |
| Add golden tests | `packs/<lang>/tests/golden.jsonl` then retrain |

See [TRAINING.md](./TRAINING.md) for full training instructions.
