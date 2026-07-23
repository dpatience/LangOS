"""Build the English lexicon and train the intent model.

Outputs:
  packs/en/lexicon.json  — every word/phrase LangOS understands, mapped to vocabulary IDs
  models/en/intent.json  — Naive Bayes intent classifier (unigram + bigram features)

Run from repo root:
  python3 -m langos_train.build
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from . import inflect
from .seed_en import GROUPS, NAMES, PRONOUNS, SYNONYMS, TEMPLATES, THINGS

SYMBOL_PREFIXES = ("ACTION_", "STATE_", "QUERY_", "EVENT_", "RELATION_", "MODIFIER_", "META_")

# Categories whose base words are verbs and get morphological expansion.
VERB_CATEGORIES = {"ACT", "STA"}

# Categories trained as utterance intents (MOD/REL are sub-sentence markers).
INTENT_CATEGORIES = {"ACT", "STA", "QRY", "EVT", "META"}

MAX_EXAMPLES_PER_CLASS = 400


def find_repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "schemas" / "semantic_vocabulary.json").exists():
            return parent
    raise SystemExit("could not locate repo root (schemas/semantic_vocabulary.json)")


def load_vocabulary(root: Path) -> list[dict]:
    doc = json.loads((root / "schemas" / "semantic_vocabulary.json").read_text())
    return doc["vocabulary"]


def base_word(symbol: str) -> str:
    """ACTION_SIGN_UP -> 'sign up'."""
    for prefix in SYMBOL_PREFIXES:
        if symbol.startswith(prefix):
            return symbol[len(prefix):].lower().replace("_", " ")
    return symbol.lower().replace("_", " ")


def surface_forms(word: str, category: str) -> list[str]:
    if category in VERB_CATEGORIES and re.fullmatch(r"[a-z]+( [a-z]+)*", word):
        return inflect.all_forms(word)
    return [word]


def build_lexicon(vocabulary: list[dict]) -> dict:
    entries: dict[str, dict] = {}

    # Pronouns and deictics claim their words first — they are never verbs here.
    for word, ref in PRONOUNS.items():
        entries[word] = {"ref": ref}

    for item in vocabulary:
        vid, symbol, category = item["id"], item["symbol"], item["category"]
        if category == "UNK":
            continue

        words = []
        if category in VERB_CATEGORIES:
            words.append(base_word(symbol))
        words.extend(SYNONYMS.get(vid, []))

        for word in words:
            word = word.strip().lower()
            if not word:
                continue
            for form in surface_forms(word, category):
                # first mapping wins: curated order is intentional
                entries.setdefault(form, {"id": vid, "symbol": symbol, "category": category})

    max_phrase_words = max(len(w.split()) for w in entries)
    return {
        "language": "en",
        "generated_by": "langos_train",
        "entry_count": len(entries),
        "max_phrase_words": max_phrase_words,
        "entries": entries,
    }


def tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def features(tokens: list[str]) -> list[str]:
    feats = list(tokens)
    feats.extend(f"{a}_{b}" for a, b in zip(tokens, tokens[1:]))
    return feats


def expand_templates(vid: str, category: str, synonyms: list[str]) -> list[str]:
    templates = TEMPLATES.get(vid) or TEMPLATES.get(f"__{category}_DEFAULT__") or []
    utterances: list[str] = []

    for template in templates:
        variants = [template]
        if "{verb}" in template:
            variants = [template.replace("{verb}", syn) for syn in synonyms]
        for variant in variants:
            fillers = [variant]
            if "{name}" in variant:
                fillers = [v.replace("{name}", n) for v in fillers for n in NAMES[:4]]
            if "{thing}" in variant:
                fillers = [v.replace("{thing}", t) for v in fillers for t in THINGS[:5]]
            if "{group}" in variant:
                fillers = [v.replace("{group}", g) for v in fillers for g in GROUPS[:3]]
            utterances.extend(fillers)

    return utterances[:MAX_EXAMPLES_PER_CLASS]


def build_corpus(vocabulary: list[dict]) -> dict[str, list[str]]:
    corpus: dict[str, list[str]] = {}
    for item in vocabulary:
        vid, symbol, category = item["id"], item["symbol"], item["category"]
        if category not in INTENT_CATEGORIES:
            continue

        synonyms = []
        if category in VERB_CATEGORIES:
            synonyms.append(base_word(symbol))
        synonyms.extend(SYNONYMS.get(vid, []))
        if not synonyms:
            continue

        utterances = expand_templates(vid, category, synonyms)
        if utterances:
            corpus[vid] = utterances
    return corpus


def train_naive_bayes(corpus: dict[str, list[str]], vocabulary: list[dict]) -> dict:
    symbol_of = {item["id"]: item["symbol"] for item in vocabulary}
    total_docs = sum(len(docs) for docs in corpus.values())

    # Shared feature vocabulary: smoothing must use one global V, otherwise
    # classes with tiny vocabularies get inflated unknown-token probabilities.
    per_class_counts: dict[str, Counter[str]] = {}
    global_features: set[str] = set()
    for vid, docs in corpus.items():
        counts: Counter[str] = Counter()
        for doc in docs:
            counts.update(features(tokenize(doc)))
        per_class_counts[vid] = counts
        global_features.update(counts)
    global_vocab_size = len(global_features) + 1

    classes: dict[str, dict] = {}
    for vid, docs in corpus.items():
        token_counts = per_class_counts[vid]
        denom = sum(token_counts.values()) + global_vocab_size  # Laplace with shared V

        # Uniform priors: corpus class frequencies are artifacts of template
        # expansion, not of real utterance distribution.
        classes[vid] = {
            "symbol": symbol_of[vid],
            "log_prior": 0.0,
            "log_default": round(math.log(1.0 / denom), 6),
            "log_likelihood": {
                token: round(math.log((count + 1) / denom), 6)
                for token, count in token_counts.items()
            },
        }

    return {
        "version": "1",
        "language": "en",
        "algorithm": "multinomial_naive_bayes",
        "features": "unigram+bigram",
        "class_count": len(classes),
        "training_examples": total_docs,
        "classes": classes,
    }


def main() -> None:
    root = find_repo_root()
    vocabulary = load_vocabulary(root)

    lexicon = build_lexicon(vocabulary)
    lexicon_path = root / "packs" / "en" / "lexicon.json"
    lexicon_path.write_text(json.dumps(lexicon, indent=1, sort_keys=True))
    print(f"lexicon: {lexicon['entry_count']} entries -> {lexicon_path}")

    corpus = build_corpus(vocabulary)
    model = train_naive_bayes(corpus, vocabulary)
    model_path = root / "models" / "en" / "intent.json"
    model_path.parent.mkdir(parents=True, exist_ok=True)
    model_path.write_text(json.dumps(model))
    print(
        f"model: {model['class_count']} classes, "
        f"{model['training_examples']} training examples -> {model_path}"
    )


if __name__ == "__main__":
    main()
