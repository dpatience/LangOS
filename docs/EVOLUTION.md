# LangOS Evolution & Growth Strategy

**Version:** 0.1.0  
**Status:** Draft — long-term strategy  
**Last updated:** 2026-07-23  
**Related:** [ARCHITECTURE.md](./ARCHITECTURE.md) · [INFRASTRUCTURE.md](./INFRASTRUCTURE.md)

---

## 1. Why This Document Exists

Building LangOS to v1.0 is only the beginning. The harder problem is **staying alive for decades** while:

- Human language changes daily (slang, new products, regional drift)
- New languages must be added without breaking existing ones
- Applications multiply (Duselang, Tembera, Iwange250, unknown future products)
- Neural models improve, but APIs and Semantic IR must remain stable

If LangOS requires a full retrain every six months, it will die. Instead it must become a **living language system**: a stable kernel with continuously updatable surfaces.

This document defines how LangOS evolves **after** initial development is complete—including the path from 3 languages to hundreds.

---

## 2. Core Thesis

```
95% of LangOS never changes     →  Kernel + Semantic IR + APIs
5% changes continuously         →  Vocabulary, regional variants, packs, neural weights
```

| Stable (rare releases) | Evolving (frequent releases) |
|------------------------|------------------------------|
| Semantic IR schema (versioned) | Vocabulary files |
| Kernel pipeline stages | Regional pack extensions |
| Public APIs (native + compat) | Slang / idiom lexicons |
| Engine behaviour contracts | Domain word lists (not business logic) |
| Reference slot semantics | Neural model checkpoints |

Applications connect once. LangOS improves underneath them.

---

## 3. The Five Evolution Layers

These layers are **independent**. Updating one must not force updating others.

### Layer 1 — Core Language (Kernel)

**Change frequency:** Rare — once or twice per year, if at all.

The kernel is language-independent. It defines:

- Semantic IR structure
- Pipeline stages (split → parse → extract → graph → export)
- Reference slot semantics (`previous_entity`, not resolved IDs)
- Engine routing (rule → stat → neural)
- API contracts (native + OpenAI/Anthropic compatibility)

The kernel understands **universal linguistic roles**, not domain meaning:

- Nouns, verbs, modifiers
- Sentence structure and dependency relations
- Questions, commands, statements
- Coreference markers (`she`, `it`, `that class`)

Example: *"Create a student called Clarissa"* — the kernel extracts `create` + entity label `student` + name `Clarissa`. It does not know what a student is in a school system.

English grammar has changed slowly for decades. The kernel targets structures that change over **decades**, not days.

---

### Layer 2 — Vocabulary Packs

**Change frequency:** Weekly to monthly (small signed updates); no kernel retrain.

Words change. Grammar does not.

```
Yeet · Ghosting · Rizz · Skibidi · LLM · vibe check
```

These must **never** require retraining the kernel or neural engines. They are **lexicon entries** downloaded as signed files:

```bash
langos pack update en-vocab --channel stable
# Downloads vocabulary v12.en.json (~200 KB), not a new model
```

Vocabulary pack contents:

| Component | Example |
|-----------|---------|
| New terms | `rizz → charisma (slang, positive)` |
| Spelling variants | `colour / color` |
| Abbreviations | `A1 → class identifier (context: education)` |
| Product names | `WhatsApp`, `M-Pesa` |
| Deprecated terms | mark `fetch` (slang) as superseded |

The kernel still does not know domain meaning. `stethoscope` is a word it can tokenize and pass through—not a medical concept it understands.

---

### Layer 3 — Regional Packs

**Change frequency:** Monthly per region; independent per locale.

One written language, many regional variants:

| Base | Regional pack | Example divergence |
|------|---------------|-------------------|
| English (`en`) | `en-US`, `en-GB`, `en-NG`, `en-KE`, `en-IN`, `en-ZA` | lift → elevator (US) |
| French (`fr`) | `fr-FR`, `fr-CA`, `fr-RW`, `fr-CD` | register, idioms |
| Arabic (`ar`) | `ar-EG`, `ar-MA`, `ar-Gulf` | dialectal vocabulary |
| Portuguese (`pt`) | `pt-PT`, `pt-BR` | grammar and lexicon |

Hierarchy:

```
Language Pack (en)
    ├── Base grammar + tokenizer
    └── Regional Extension (en-NG)
            ├── Lexical mappings
            ├── Idiom tables
            └── Spelling preferences
```

Regional packs **override outbound generation** (express path) and **disambiguate inbound** (understand path). The Semantic IR produced is the same; only surface forms differ.

Rwanda-relevant example — Kinyarwanda pack with French/English code-switching extensions:

```
"Ongeramo Clarissa muri Biology A1"  →  same IR as English/French equivalents
"Nshaka ko yiga mu French"           →  preferred_language: French
```

---

### Layer 4 — Community Learning (Controlled)

**Change frequency:** Continuous observation; human-gated release.

Thousands of applications generate language LangOS has never seen. **Automatic learning is dangerous** (poisoning, PII, adversarial input). LangOS uses a **observe → aggregate → review → release** pipeline:

```text
Unknown / low-confidence expression
        │
        ▼
Frequency + context counters (anonymous, aggregated)
        │
        ▼
Meaning candidates (clustered by embedding similarity)
        │
        ▼
Human review (LangOS language team or community curators)
        │
        ▼
Golden test added
        │
        ▼
Signed vocabulary or regional pack update
```

Example:

100,000 student users write *"This assignment is fire."*

LangOS records (without storing raw conversations):

```json
{
  "token": "fire",
  "context_tags": ["school", "assignment", "positive_sentiment"],
  "occurrences": 98420,
  "candidate_senses": ["excellent", "impressive"]
}
```

After review, Vocabulary Pack `en-vocab v18` adds:

```yaml
fire:
  sense: excellent
  register: slang
  context: [positive, evaluation]
  confidence: human_verified
```

No retraining. Next request resolves correctly.

#### Application feedback loop (post-v1.0)

Applications like Duselang can optionally report **corrections**, not raw chat:

```json
{
  "type": "correction",
  "original_ir": { "...": "..." },
  "corrected_ir": { "...": "..." },
  "locale": "en-NG",
  "domain_hint": "education"
}
```

Corrections enter the review queue. They improve packs for **all** connected applications—not just the reporter.

---

### Layer 5 — Neural Improvement

**Change frequency:** Quarterly to annually per engine; API-stable.

Neural engines (`langos-parse-v2`, `langos-express-v2`) improve parsing, semantics, and fluency. Releases are **invisible to applications** if:

1. Semantic IR schema version is unchanged (or backward compatible)
2. Golden tests pass for all installed language packs
3. Compatibility API responses remain shape-identical

```text
langos-parse-v1  →  langos-parse-v2  →  langos-parse-v3
        │                    │                    │
        └────────────────────┴────────────────────┘
                    Same /understand API
                    Same Semantic IR v1.0 export
```

Neural upgrades are **per language pack**, not global:

```
en neural parse v3  (ready)
fr neural parse v2  (ready)
rw neural parse v1  (bootstrap)
sw neural parse v1  (planned)
```

Upgrading English neural weights does not touch Kinyarwanda.

---

## 4. Pack Hierarchy (Complete Model)

```text
LangOS
│
├── Kernel                          (rare releases)
│
├── Language Packs                  (per language, independent lifecycle)
│      ├── en · fr · rw · tr · de · ar · sw · …
│      Each contains:
│         ├── Tokenizer
│         ├── Grammar / parse rules
│         ├── Neural model slots (parse, generate, coref)
│         ├── Express templates
│         └── Golden test corpus
│
├── Regional Packs                  (locale extensions)
│      ├── en-US · en-GB · en-NG · fr-RW · …
│
├── Vocabulary Packs                (domain words only — not business logic)
│      ├── education-vocab
│      ├── medical-vocab
│      ├── transport-vocab
│      └── agriculture-vocab
│
└── Style Packs                     (generation register)
       ├── formal · casual · child · academic · concise
```

**Critical rule:** Vocabulary and style packs contain **words and phrasing**, never intents, permissions, or business rules.

---

## 5. Training Strategy (How LangOS Differs from Today's LLMs)

Today's LLM pattern:

```text
Collect 20T tokens → Train monolith → Deploy → Repeat from scratch
```

LangOS pattern:

```text
Foundation weights (bootstrap once per engine type)
        │
        ▼
Per-language pack fine-tune (parallel, isolated)
        │
        ▼
Vocabulary + regional overlays (no train — lexicon merge)
        │
        ▼
Community-reviewed updates (no train — lexicon merge)
        │
        ▼
Periodic neural retrain (quarterly/yearly, per pack, gated by golden tests)
```

### What gets trained vs what gets edited

| Update type | Method | Downtime | Cost |
|-------------|--------|----------|------|
| New slang term | Vocabulary file | Zero | ~$0 |
| Regional idiom | Regional pack file | Zero | ~$0 |
| New language (Phase A) | Rule + stat pack only | Zero | Low |
| New language (Phase B) | + Fine-tuned neural pack | Zero (hot swap) | Medium |
| Neural engine v2 | Replace ONNX/GGUF artifact | Zero (rolling) | Medium–High |
| Kernel / IR v2 | Coordinated release | Planned | High (rare) |

---

## 6. Adding New Languages at Scale

**Never retrain everything.** Each language is an isolated pack on the same kernel.

### 6.1 Language Maturity Tiers

Not every language starts at full quality. LangOS ships **tiered packs** so a language can go live early and mature over time:

| Tier | Name | Capabilities | Target latency |
|------|------|--------------|----------------|
| T0 | **Presence** | Language detection, script identification | Immediate |
| T1 | **Commands** | Rule engine, high-frequency patterns, short sentences | Week 1 of pack work |
| T2 | **Conversation** | Stat engine NER, reference markers, multi-sentence | Month 1–3 |
| T3 | **Documents** | Neural parse, long-text streaming, coreference | Month 3–9 |
| T4 | **Fluent** | Full neural generate, style packs, regional variants | Month 9–18 |

Example rollout for Swahili (`sw`):

```text
Month 0:  T0 + T1  —  Duselang can detect Swahili commands in mixed classrooms
Month 4:  T2       —  Multi-turn registration dialogues
Month 8:  T3       —  Teacher performance paragraphs
Month 14: T4       —  Fluent parent communication letters
```

English and French do not regress when Swahili advances.

### 6.2 New Language Playbook

For each new language `xx`:

```text
1. Script & tokenization study
      Arabic (RTL), Chinese (no spaces), Amharic (Ge'ez script)

2. Collect parallel corpus
      xx ↔ Semantic IR pairs (not xx ↔ English — IR is the pivot)

3. Ship T1 rule pack
      500–2000 golden command patterns

4. Fine-tune stat + neural on pack-specific data
      Train in Python; deploy as langos-parse-xx-v1 ONNX

5. Regional variants
      e.g. fr-RW after fr base

6. Connect to Language Observatory
      Low-confidence queue for xx-specific unknowns

7. Promote tier when golden test accuracy thresholds met
```

### 6.3 Cross-Language Transfer (Bootstrapping Acceleration)

Languages are isolated at **runtime**, but **training** can share signal:

| Technique | Use |
|-----------|-----|
| Shared Semantic IR labels | Same `create`, `register`, `assign` predicates across all languages |
| Multilingual base model | One bootstrap encoder fine-tuned per language head |
| Typological clusters | Bantu languages (rw, sw, ln) share tokenizer strategies |
| Parallel seed sets | 10,000 IR-aligned sentences translated professionally per new language |
| Synthetic generation | Express templates generate training pairs from IR |

This means language #50 is **faster to reach T3** than language #3 was—not because the kernel changed, but because training infrastructure and IR corpora accumulated.

### 6.4 Languages with Low Digital Resource

For languages with little online text (many African, indigenous, and oral-first languages):

```text
Phase A — Community sentence collection
    Partner with applications (schools, clinics) for consented phrase donations

Phase B — Rule-heavy T1 pack
    Elders / linguists define core grammar patterns manually

Phase C — Small neural fine-tune
    Train on thousands (not billions) of IR-aligned pairs

Phase D — Observatory-driven growth
    Real usage from Duselang/Tembera feeds the review queue
```

Low-resource is not low-priority—it defines LangOS's long-term moat in markets others ignore.

### 6.5 Target Language Roadmap (Illustrative)

| Wave | Languages | Rationale |
|------|-----------|-----------|
| Wave 0 (launch) | `en`, `fr`, `rw` | Duselang, Rwanda, Francophone Africa |
| Wave 1 | `sw`, `ar`, `pt`, `tr` | East Africa, MENA, Brazil, Turkey |
| Wave 2 | `ha`, `yo`, `am`, `ln`, `zu` | West/Southern Africa, Ethiopia |
| Wave 3 | `de`, `es`, `hi`, `zh`, `ja` | Global coverage, large user bases |
| Wave 4 | Community-requested | Driven by application demand + Observatory data |

Each wave adds packs only. Kernel version unchanged.

---

## 7. Language Observatory

The Language Observatory is LangOS's **immune system and radar**—how the platform senses language change across the world.

### 7.1 What It Collects (Opt-In Only)

Instances contribute **anonymous aggregated signals**, never raw conversations:

| Signal | Purpose |
|--------|---------|
| Unknown token frequency | Detect emerging slang |
| Low-confidence parse rate | Find grammar gaps |
| Correction reports | Human-validated improvements |
| Regional spelling drift | Update regional packs |
| New entity label patterns | Vocabulary hints (not schema) |
| Cross-language code-switch rate | Prioritise multilingual packs |

Example aggregate:

```json
{
  "token": "rizz",
  "locale_hints": { "en-US": 2000000, "en-GB": 400000, "en-NG": 180000 },
  "embedding_neighbors": ["charisma", "charm", "appeal"],
  "status": "candidate",
  "review_queue": "en-vocab"
}
```

### 7.2 What It Never Does Automatically

- Modify the kernel
- Retrain neural weights
- Store user messages
- Push updates without signature verification

### 7.3 Release Pipeline

```text
Observatory candidates
        │
        ▼
Curator review (human)
        │
        ▼
Golden test added
        │
        ▼
Staging pack published
        │
        ▼
Canary rollout (1% of instances)
        │
        ▼
Stable channel release
        │
        ▼
Rollback available (pack version pin)
```

### 7.4 Federation Model (Post-v1.0)

| Role | Responsibility |
|------|----------------|
| **LangOS Core Team** | Kernel, Observatory infrastructure, pack signing keys |
| **Language Curators** | Per-language review (native speakers) |
| **Application Partners** | Duselang, Tembera — submit corrections, fund low-resource packs |
| **Community** | Propose vocabulary via authenticated PRs to open lexicon repos |

---

## 8. Post-v1.0 Improvement Flywheel

LangOS gets better forever through a closed loop that does not require rebuilding:

```text
                    ┌─────────────────────────┐
                    │   Applications use      │
                    │   LangOS (Duselang…)    │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        Translations      Low-confidence      Corrections
        (logged opt-in)   signals             (explicit)
              │                 │                 │
              └─────────────────┼─────────────────┘
                                ▼
                    ┌─────────────────────────┐
                    │   Language Observatory  │
                    └───────────┬─────────────┘
                                ▼
                    ┌─────────────────────────┐
                    │   Review + golden tests │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        Vocabulary          Regional          Neural retrain
        pack update         pack update       (scheduled)
              │                 │                 │
              └─────────────────┼─────────────────┘
                                ▼
                    ┌─────────────────────────┐
                    │   All applications      │
                    │   improve automatically │
                    └─────────────────────────┘
```

Every product on LangOS makes LangOS better for every other product—without sharing business logic or conversation data.

---

## 9. Versioning & Release Cadence

| Artifact | Version format | Cadence | Breaking changes |
|----------|----------------|---------|------------------|
| Kernel | `kernel-2026.1` | 1–2× / year | Rare; IR migration guide |
| Semantic IR | `1.0`, `1.1`, `2.0` | Major every 2–3 years | Explicit export profiles |
| Language pack | `en-2.4.1` | Monthly (tier upgrades) | Never breaks IR |
| Vocabulary pack | `en-vocab-18` | Weekly | Never breaks IR |
| Regional pack | `en-NG-3.1` | Monthly | Never breaks IR |
| Neural artifact | `langos-parse-en-v3` | Quarterly | Hot-swappable |
| Compatibility API | `2026-07-23` | Stable indefinitely | Never breaks clients |

### Pack channels

```bash
langos pack install en --channel stable     # production
langos pack install en --channel beta       # early vocabulary
langos pack install en --channel canary     # Observatory candidates
langos pack pin en-vocab-17                 # rollback
```

---

## 10. Quality Gates (Nothing Regresses)

Every pack or model update must pass:

1. **Golden tests** — fixed text → expected Semantic IR (per language, per tier)
2. **Compatibility contract tests** — OpenAI/Anthropic response shapes unchanged
3. **Cross-language IR consistency** — same meaning in en/fr/rw → equivalent IR predicates
4. **Latency budget** — no >10% regression on benchmark suite
5. **Human spot-check** — 50 random Observatory fixes reviewed before stable release

Languages cannot advance tier until their golden suite passes at the target tier.

---

## 11. Long-Term Vision: LangOS at 100+ Languages

When LangOS supports 100+ languages, the competitive advantage is not any single model—it is the **system**:

| Capability | Why it compounds |
|------------|------------------|
| Semantic IR as universal pivot | Add language #101 without touching #1–100 |
| Tiered maturity | Ship early, improve in production |
| Observatory | Real-world signal from every connected app |
| Vocabulary without retrain | Daily language change absorbed cheaply |
| API compatibility | Applications never migrate again |
| Isolated pack failures | Bug in `ha` pack does not affect `ja` |
| Cross-language training infra | Each new language costs less than the last |

LangOS becomes **infrastructure**—like DNS or TLS—not a product that ages.

---

## 12. Summary

| Layer | What evolves | How | Frequency |
|-------|--------------|-----|-----------|
| 1 — Kernel | Parsing pipeline, IR schema | Coordinated release | Rare |
| 2 — Vocabulary | Words, slang, terms | Signed lexicon files | Weekly |
| 3 — Regional | Locale variants | Signed regional packs | Monthly |
| 4 — Community | Unknown → verified meaning | Observatory + review | Continuous → weekly releases |
| 5 — Neural | Parse/generate quality | Per-language model artifacts | Quarterly |

**After v1.0 is "finished," LangOS never stops improving—because language never stops changing.**

The goal is not a perfect frozen model. The goal is a **living system** that absorbs change at the right layer, at the right cost, without breaking the applications that depend on it.

---

## 13. Open Questions

1. **Curator governance** — who certifies regional packs for `rw` vs `fr-RW`?
2. **Observatory privacy** — differential privacy thresholds before aggregate publish?
3. **Tier commercial model** — do T1 languages ship free while T4 requires subscription?
4. **Code-switching** — single pack vs `en-rw-mixed` composite pack?
5. **Right-to-left generation** — express path mirroring for `ar`, `he`, `ur`?

These will be resolved as Wave 0 languages reach T4 maturity.
