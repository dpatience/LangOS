"""Train lexicon + intent model for any language pack under packs/<lang>/.

Uses:
  - packs/<lang>/patterns/commands.json  (verb_map, pronoun_map)
  - packs/<lang>/tests/golden.jsonl      (labeled utterances)
  - schemas/semantic_vocabulary.json     (stable vocab IDs)

Outputs:
  - packs/<lang>/lexicon.json
  - models/<lang>/intent.json

English (en) still uses seed_en.py via build.py for richer coverage.

Run from repo root:
  python3 -m langos_train.build_pack --lang fr
  python3 -m langos_train.build_pack --all
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import Counter
from pathlib import Path

from .build import features, find_repo_root, load_vocabulary, tokenize, train_naive_bayes

SUPPORTED = ("en", "fr", "de", "tr", "rw")
NAMES = ("Alice", "Clarissa", "Bob", "Marie", "Jean", "Paul")
THINGS = ("Biology A1", "Math 101", "the class", "the group", "the file")


def symbol_index(vocabulary: list[dict]) -> dict[str, dict]:
    return {item["symbol"]: item for item in vocabulary}


def normalize_verb_entry(value) -> tuple[str, str] | None:
    if isinstance(value, dict):
        vid = value.get("id")
        sym = value.get("symbol")
        if vid and sym:
            return vid, sym
    if isinstance(value, str):
        return value, value
    return None


def load_patterns(root: Path, lang: str) -> dict:
    path = root / "packs" / lang / "patterns" / "commands.json"
    if not path.exists():
        raise SystemExit(f"missing pack patterns: {path}")
    return json.loads(path.read_text())


def build_lexicon_from_pack(lang: str, patterns: dict, vocabulary: list[dict]) -> dict:
    by_symbol = symbol_index(vocabulary)
    entries: dict[str, dict] = {}

    for word, raw in patterns.get("verb_map", {}).items():
        normalized = normalize_verb_entry(raw)
        if not normalized:
            continue
        vid, sym = normalized
        if sym in by_symbol:
            vid = by_symbol[sym]["id"]
            category = by_symbol[sym]["category"]
        elif not vid.startswith(("ACT_", "STA_", "QRY_", "EVT_", "META_")):
            continue
        else:
            category = vid[:3]
        word = word.strip().lower()
        if word:
            entries.setdefault(word, {"id": vid, "symbol": sym, "category": category})

    for word, ref in patterns.get("pronoun_map", {}).items():
        word = word.strip().lower()
        if word:
            entries.setdefault(word, {"ref": ref})

    for word in patterns.get("detection", {}).get("words", []):
        word = word.strip().lower()
        if word and word not in entries:
            entries[word] = {"category": "MOD"}

    max_phrase_words = max((len(w.split()) for w in entries), default=1)
    return {
        "language": lang,
        "generated_by": "langos_train.build_pack",
        "entry_count": len(entries),
        "max_phrase_words": max_phrase_words,
        "entries": entries,
    }


def load_golden(root: Path, lang: str) -> list[tuple[str, str]]:
    path = root / "packs" / lang / "tests" / "golden.jsonl"
    if not path.exists():
        return []

    pairs: list[tuple[str, str]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        doc = json.loads(line)
        text = doc.get("input", {}).get("text") or doc.get("text")
        vid = doc.get("expected", {}).get("vocab_id") or doc.get("vocab_id")
        if text and vid:
            pairs.append((text, vid))
    return pairs


def synthetic_utterances(lang: str, verb: str, vid: str) -> list[str]:
    verb = verb.lower()
    samples = [
        f"{verb} Alice",
        f"{verb} Clarissa",
        f"please {verb} Alice",
        f"{verb} {THINGS[0]}",
        f"{verb} Alice to {THINGS[0]}",
    ]

    if lang == "fr":
        samples.extend([
            f"{verb} Alice à {THINGS[0]}",
            f"{verb} Clarissa dans {THINGS[0]}",
        ])
    elif lang == "de":
        samples.extend([
            f"{verb} Alice in {THINGS[0]}",
            f"bitte {verb} Alice",
        ])
    elif lang == "tr":
        samples.extend([
            f"lütfen {verb} Alice",
            f"{verb} Alice'yi {THINGS[0]}",
        ])
    elif lang == "rw":
        samples.extend([
            f"{verb} Alice muri {THINGS[0]}",
            f"nyamuneka {verb} Alice",
        ])

    return [s for s in samples if re.search(r"[a-zA-Z\u00C0-\u024F\u0400-\u04FF]", s)]


def build_corpus_from_pack(
    lang: str, patterns: dict, vocabulary: list[dict], golden: list[tuple[str, str]]
) -> dict[str, list[str]]:
    by_symbol = symbol_index(vocabulary)
    corpus: dict[str, list[str]] = {}

    for text, vid in golden:
        corpus.setdefault(vid, []).append(text)

    for word, raw in patterns.get("verb_map", {}).items():
        normalized = normalize_verb_entry(raw)
        if not normalized:
            continue
        vid, sym = normalized
        if sym in by_symbol:
            vid = by_symbol[sym]["id"]
        if not vid.startswith(("ACT_", "STA_", "QRY_", "EVT_", "META_")):
            continue
        for utterance in synthetic_utterances(lang, word, vid):
            corpus.setdefault(vid, []).append(utterance)

    return {vid: docs[:400] for vid, docs in corpus.items() if docs}


def train_language(root: Path, lang: str, vocabulary: list[dict]) -> None:
    if lang == "en":
        from .build import build_corpus, build_lexicon, main as build_en

        build_en()
        return

    patterns = load_patterns(root, lang)
    golden = load_golden(root, lang)

    lexicon = build_lexicon_from_pack(lang, patterns, vocabulary)
    lexicon_path = root / "packs" / lang / "lexicon.json"
    lexicon_path.write_text(json.dumps(lexicon, indent=1, sort_keys=True))
    print(f"[{lang}] lexicon: {lexicon['entry_count']} entries -> {lexicon_path}")

    corpus = build_corpus_from_pack(lang, patterns, vocabulary, golden)
    if not corpus:
        print(f"[{lang}] warning: empty training corpus — add golden.jsonl or verb_map entries")
        return

    model = train_naive_bayes(corpus, vocabulary)
    model["language"] = lang
    model_path = root / "models" / lang / "intent.json"
    model_path.parent.mkdir(parents=True, exist_ok=True)
    model_path.write_text(json.dumps(model))
    print(
        f"[{lang}] model: {model['class_count']} classes, "
        f"{model['training_examples']} examples -> {model_path}"
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Train LangOS pack lexicon + intent model")
    parser.add_argument("--lang", choices=SUPPORTED, help="language code")
    parser.add_argument("--all", action="store_true", help="train all supported languages")
    args = parser.parse_args(argv)

    if not args.lang and not args.all:
        parser.error("pass --lang <code> or --all")

    root = find_repo_root()
    vocabulary = load_vocabulary(root)
    langs = list(SUPPORTED) if args.all else [args.lang]

    for lang in langs:
        manifest = root / "packs" / lang / "manifest.json"
        if not manifest.exists():
            print(f"[{lang}] skip — no pack at packs/{lang}/")
            continue
        train_language(root, lang, vocabulary)


if __name__ == "__main__":
    main()
