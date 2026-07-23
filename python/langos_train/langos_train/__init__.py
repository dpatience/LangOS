"""LangOS offline training pipelines.

- `langos_train.build` — builds the lexicon (packs/<lang>/lexicon.json) and
  trains the Naive Bayes intent model (models/<lang>/intent.json) for English.
- `langos_train.build_pack` — same for fr, de, tr, rw (and `--all`).
- `langos_train.inflect` — English morphological expansion.
- `langos_train.seed_en` — curated synonyms and utterance templates.

Run: python3 -m langos_train.build
"""

__all__: list[str] = []
