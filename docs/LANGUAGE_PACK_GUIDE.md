# Language Pack Creation Guide

How to teach LangOS a new language — by creating a language pack.

## Overview

A language pack is a folder under `packs/<language_code>/` that teaches LangOS
how to **understand** (parse) and **speak** (generate) in a language. LangOS
reads these files at startup — no Elixir code changes are needed. Just create
the folder, add the required files, run `patience install language <code>`,
then `patience train --lang <code>` to build the statistical model.

See also: [TRAINING.md](./TRAINING.md) · [MODEL_vs_PACK.md](./MODEL_vs_PACK.md)

## Quick start

```
packs/
└── xx/                          ← your ISO 639-1 language code
    ├── manifest.json            ← identity & capabilities
    ├── grammar.json             ← the 8 parts of speech + rules
    ├── patterns/
    │   └── commands.json        ← understanding: regex patterns + verb/pronoun maps
    ├── templates/
    │   └── express/             ← (optional) legacy fill-in templates
    │       ├── success.json
    │       ├── error.json
    │       └── ...
    └── tests/
        └── golden.jsonl         ← test cases for your language
```

## Step 1 — `manifest.json`

Declares who the pack is:

```json
{
  "id": "xx",
  "version": "1.0.0",
  "name": "Language Name (in that language)",
  "direction": "ltr",
  "capabilities": ["understand", "express", "tokenize"],
  "default_locale": "xx-XX",
  "requires": {
    "kernel": ">=1.0.0"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | Yes | ISO 639-1 code: `en`, `fr`, `de`, `ar`, `zh`, `ru`, … |
| `name` | Yes | The language's name in itself (e.g. "Deutsch", "العربية") |
| `direction` | Yes | `"ltr"` or `"rtl"` (Arabic, Hebrew) |
| `capabilities` | Yes | Which pipeline stages the pack supports |

## Step 2 — `grammar.json` (the brain)

This is the most important file. It teaches LangOS the **8 parts of speech**
for your language and how they combine to form sentences.

### Top-level structure

```json
{
  "language": "xx",
  "script": "latin",
  "word_order": "SVO",
  "morphology": { ... },
  "sentence_rules": { ... },
  "elision": [ ... ],
  "nouns": { ... },
  "pronouns": { ... },
  "verbs": { ... },
  "adjectives": { ... },
  "adverbs": { ... },
  "prepositions": { ... },
  "conjunctions": { ... },
  "interjections": { ... },
  "list": { ... },
  "possessive": { ... },
  "intents": { ... }
}
```

### 2.1 Metadata

| Field | Values | Example |
|---|---|---|
| `script` | `"latin"`, `"cyrillic"`, `"arabic"`, `"cjk"`, `"devanagari"`, `"hangul"`, `"ethiopic"`, … | `"latin"` |
| `word_order` | `"SVO"`, `"SOV"`, `"VSO"`, `"VOS"`, `"OVS"`, `"OSV"` | `"SVO"` for English, `"SOV"` for Turkish |

### 2.2 Morphology

Tells LangOS how words inflect in your language.

**Isolating / Fusional** (English, French, German — pre-stored verb forms):
```json
{
  "type": "fusional",
  "conjugation": "lexical"
}
```

**Agglutinative + prefix** (Kinyarwanda — subject prefix on verb stem):
```json
{
  "type": "agglutinative",
  "conjugation": "prefix",
  "prefix_key": "prefix",
  "default_prefix": "ara"
}
```

**Agglutinative + suffix** (Turkish — vowel-harmony suffixes):
```json
{
  "type": "agglutinative",
  "conjugation": "suffix",
  "vowel_harmony": {
    "vowels": ["a","e","ı","i","o","ö","u","ü"],
    "back": ["a","ı","o","u"],
    "front": ["e","i","ö","ü"],
    "harmony4": {"a":"ı", "ı":"ı", "e":"i", "i":"i", "o":"u", "u":"u", "ö":"ü", "ü":"ü"},
    "harmony2": {"back":"a", "front":"e"},
    "default": "i"
  },
  "progressive": {
    "template": "{stem_drop_vowel}{h4}yor{person}",
    "persons": {"1s":"um", "2s":"sun", "3s":"", "1p":"uz", "2p":"sunuz", "3p":"lar"}
  },
  "genitive": {"vowel_buffer": "n"},
  "accusative": {"vowel_buffer": "y"},
  "dative": {"vowel_buffer": "y"}
}
```

### 2.3 Sentence rules

```json
{
  "capitalize_first": true,
  "default_subject": "someone",
  "command_subject": null,
  "adjective_position": "before",
  "adverb_position": "before_verb"
}
```

- `adjective_position`: `"before"` (English, German, Turkish) or `"after"` (French, Kinyarwanda)
- `adverb_position`: `"before_verb"`, `"after_verb"`, or `"flexible"`
- `default_subject`: What to use when no subject is specified (null = omit subject, e.g. Kinyarwanda encodes it in the verb prefix)

### 2.4 The 8 parts of speech

#### 1. Nouns

```json
{
  "articles": {
    "definite": "the",
    "indefinite": "a",
    "indefinite_before_vowel": "an"
  },
  "gender": "none",
  "plural_rules": [ ... ],
  "field_nouns": {
    "age": "age",
    "name": "name",
    "email": "email address"
  }
}
```

`gender` can be `"none"` (English, Turkish), `"masculine_feminine"` (French),
`"masculine_feminine_neuter"` (German), or `"noun_class"` (Kinyarwanda).

`field_nouns` maps machine field names to the language's display forms.
For languages with possessed forms (Turkish), use an object:
```json
"age": {"base": "yaş", "poss": "yaşı"}
```

#### 2. Pronouns

Map reference IDs to surface forms in each grammatical case:

```json
{
  "REF_SPEAKER": {
    "subject": "I", "object": "me", "possessive": "my",
    "reflexive": "myself", "person": "1s"
  },
  "REF_LISTENER": {
    "subject": "you", "object": "you", "possessive": "your",
    "person": "2s"
  }
}
```

The `person` key (`"1s"`, `"2s"`, `"3s"`, `"1p"`, `"2p"`, `"3p"`) drives verb
conjugation. For prefix languages, add a `"prefix"` key instead.

#### 3. Verbs

Map semantic symbols to surface forms:

```json
{
  "ACTION_CREATE": {
    "imp": "create",
    "stmt": "created",
    "stmt_1s": "created",
    "gerund": "creating",
    "infinitive": "to create"
  }
}
```

| Key | Usage |
|---|---|
| `imp` | Imperative / command form |
| `stmt` | Statement form (3rd person) |
| `stmt_1s` | 1st person singular override (if different) |
| `gerund` | Present participle / -ing form |
| `infinitive` | Infinitive form |
| `stem` | For agglutinative languages: the root to which prefixes/suffixes attach |
| `fixed` | Unchanging form (for interjection-like verbs: greetings, thanks) |

#### 4. Adjectives

```json
{
  "position": "before",
  "agreement": "none",
  "common": {
    "good": {"comparative": "better", "superlative": "best"},
    "big": {"comparative": "bigger", "superlative": "biggest"},
    "important": {"comparative": "more important", "superlative": "most important"},
    "missing": {},
    "required": {}
  }
}
```

`agreement` values: `"none"` (English, Turkish), `"gender_number"` (French),
`"gender_case"` (German), `"noun_class"` (Kinyarwanda).

#### 5. Adverbs

```json
{
  "position": "before_verb",
  "formation_suffix": "ly",
  "common": {
    "quickly": {},
    "slowly": {},
    "very": {"type": "intensifier"},
    "not": {"type": "negation"},
    "please": {"type": "politeness"}
  }
}
```

#### 6. Prepositions

Map semantic roles to the language's prepositions (or postpositions):

```json
{
  "container": "in",
  "goal": "to",
  "source": "from",
  "beneficiary": "for",
  "instrument": "with",
  "location": "at",
  "about": "about"
}
```

For languages that use case suffixes instead of prepositions (Turkish),
leave the entry empty or null — the morphology engine handles it.

#### 7. Conjunctions

```json
{
  "coordinating": {
    "and": "and", "or": "or", "but": "but", "so": "so"
  },
  "subordinating": {
    "because": "because", "if": "if", "when": "when",
    "while": "while", "although": "although"
  }
}
```

#### 8. Interjections

Categorized expressions that LangOS picks from randomly:

```json
{
  "greeting": ["hello", "hi", "hey"],
  "farewell": ["goodbye", "bye", "see you"],
  "thanks": ["thank you", "thanks"],
  "surprise": ["oh", "wow"],
  "agreement": ["yes", "sure", "absolutely"],
  "disagreement": ["no", "not really"],
  "hesitation": ["well", "um", "hmm"],
  "apology": ["sorry", "excuse me"],
  "encouragement": ["great", "nice", "perfect"],
  "frustration": ["oops", "oh no"]
}
```

### 2.5 List grammar

How your language joins lists ("A, B, and C"):

```json
{
  "and": "and",
  "or": "or",
  "oxford": true
}
```

- English uses Oxford comma: `"A, B, and C"`
- Most other languages don't: `"A, B et C"` (French)
- Kinyarwanda elides: `"A, B n'C"` (when C starts with a vowel)

```json
{
  "and": "na",
  "or": "cyangwa",
  "oxford": false,
  "elide_before_vowel": "n'"
}
```

### 2.6 Possessive construction

How your language says "X's Y":

| Type | Pattern | Languages |
|---|---|---|
| `pattern` | `{owner}'s {thing}` | English |
| `pattern` | `{thing} de {owner}` | French (with `elide_before_vowel`) |
| `pattern` | `{thing} bya {owner}` | Kinyarwanda |
| `pattern` | `{thing} von {owner}` | German |
| `genitive` | Vowel-harmony genitive suffix | Turkish |

### 2.7 Intents (communication recipes)

Intent recipes compose with grammar rules to produce varied sentences.
Each intent has optional openers per tone and recipe templates:

```json
{
  "missing_fields": {
    "openers": {
      "neutral": ["Quick note:", "Before we continue:"],
      "casual": ["Almost there —"],
      "formal": []
    },
    "recipes": [
      {"tones": ["formal"], "text": "could you please provide {fields_of}?"},
      {"tones": ["neutral"], "text": "we still need {fields_of}."},
      {"tones": ["casual"], "text": "we just need {fields_of}."}
    ]
  }
}
```

Available slots: `{fields}`, `{fields_of}`, `{entity}`, `{action}`,
`{reason}`, `{name}`, `{summary}`, `{be}`.

## Step 3 — `patterns/commands.json` (understanding)

Teaches LangOS to recognize sentences in your language:

```json
{
  "patterns": [
    {
      "id": "register_in",
      "pattern": "registrier(?:e|en)\\s+(.+?)\\s+in\\s+(.+?)\\.?$",
      "vocab_id": "ACT_000005",
      "symbol": "ACTION_REGISTER",
      "unit_type": "command",
      "groups": [
        {"index": 1, "role": "patient", "kind": "named"},
        {"index": 2, "role": "container", "kind": "named"}
      ]
    }
  ],
  "verb_map": {
    "registriere": "ACTION_REGISTER",
    "erstelle": "ACTION_CREATE"
  },
  "pronoun_map": {
    "ich": "REF_SPEAKER",
    "du": "REF_LISTENER"
  },
  "detection": {
    "words": ["ich", "du", "und", "oder", "ist", "nicht", "bitte"],
    "strip_prefixes": [],
    "strip_suffixes": []
  }
}
```

**Key sections:**

- **patterns** — Regex patterns that match sentence structures. Each captures
  groups mapped to semantic roles.
- **verb_map** — Surface verb → semantic symbol. Used by language detection
  and the syntax engine.
- **pronoun_map** — Surface pronoun → reference ID.
- **detection** — High-frequency words for language detection. For
  agglutinative languages, `strip_prefixes` or `strip_suffixes` let the
  detector probe morphologically transformed verbs.

## Step 4 — `tests/golden.jsonl` (test cases)

Each line is a JSON object testing understanding:

```jsonl
{"input": "Registriere Hans in Biologie A1", "locale": "de", "expected": {"symbol": "ACTION_REGISTER"}}
{"input": "Hallo!", "locale": "de", "expected": {"symbol": "META_GREET"}}
{"input": "Was ist Photosynthese?", "locale": "de", "expected": {"symbol": "ACTION_DEFINE", "utterance_type": "question"}}
```

Run with: `mix test test/golden_test.exs`

## Step 5 — Install, train & test

### Option A: Config file (permanent)

Add your language code to `config/langos.json`:

```json
"language_packs": {
  "installed": ["en", "fr", "rw", "tr", "de", "xx"]
}
```

### Option B: CLI (hot install, current session)

```bash
patience install language xx
patience train --lang xx          # build lexicon + intent model
```

### Test it

```bash
# Understanding
patience understand --text "your sentence here" --locale xx

# Expression
patience express --template missing_fields --tone neutral --locale xx \
  --data '{"entity":"Alice", "fields":"age, email"}'

# Run golden tests
mix test test/golden_test.exs
```

## Reference: supported scripts

LangOS detects these writing systems automatically and routes to
packs that declare the matching `script`:

| Script value | Writing system | Unicode block |
|---|---|---|
| `latin` | Latin alphabet | Default |
| `cyrillic` | Russian, Ukrainian, Serbian… | `\p{Cyrillic}` |
| `arabic` | Arabic, Farsi, Urdu… | `\p{Arabic}` |
| `cjk` | Chinese characters | `\p{Han}` |
| `hangul` | Korean | `\p{Hangul}` |
| `devanagari` | Hindi, Sanskrit, Nepali… | `\p{Devanagari}` |
| `hiragana` | Japanese (hiragana) | `\p{Hiragana}` |
| `katakana` | Japanese (katakana) | `\p{Katakana}` |
| `thai` | Thai | `\p{Thai}` |
| `hebrew` | Hebrew | `\p{Hebrew}` |
| `ethiopic` | Amharic, Tigrinya… | `\p{Ethiopic}` |
| `bengali` | Bengali, Assamese | `\p{Bengali}` |
| `georgian` | Georgian | `\p{Georgian}` |
| `greek` | Greek | `\p{Greek}` |
| `tamil` | Tamil | `\p{Tamil}` |
| `telugu` | Telugu | `\p{Telugu}` |
| `myanmar` | Burmese | `\p{Myanmar}` |

## Tips for a good pack

1. **Start with detection words** — list 50+ high-frequency function words
   so LangOS recognizes the language reliably.

2. **Cover the common verbs** — the verb_map is the backbone of understanding.
   Aim for 50+ entries with both infinitive and conjugated forms.

3. **Write varied intent recipes** — 6-10 recipes per intent across 3 tones
   makes LangOS sound human, not robotic.

4. **Test edge cases** — add golden tests for suffix-stripped verbs,
   elision, compound words, and questions.

5. **Teach all 8 parts of speech** — even if some sections are small,
   having them all present lets LangOS grow its capabilities for your language.

## Semantic symbols reference

See `schemas/semantic_vocabulary.json` for the full list. The most common:

| Symbol | Meaning |
|---|---|
| `ACTION_CREATE` | Create something |
| `ACTION_DELETE` | Delete/remove |
| `ACTION_REGISTER` | Register/enroll |
| `ACTION_SEND` | Send/transmit |
| `ACTION_SHOW` | Show/display |
| `ACTION_SEARCH` | Search/find |
| `STATE_WANT` | Desire |
| `STATE_KNOW` | Knowledge |
| `STATE_LOVE` | Affection |
| `META_GREET` | Greeting |
| `META_THANK` | Gratitude |
| `META_FAREWELL` | Goodbye |

## Questions?

Open an issue or contact the LangOS team. Every language pack helps LangOS
understand and speak to more people.
