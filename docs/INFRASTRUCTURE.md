# LangOS Infrastructure Document

**Version:** 0.2.0  
**Status:** Current  
**Last updated:** 2026-07-23

---

## 1. Purpose

This document specifies the **engineering infrastructure** required to build, deploy, operate, and scale LangOS. It complements [ARCHITECTURE.md](./ARCHITECTURE.md), which defines *what* the system does. This document defines *how* it is built and run.

LangOS is a **self-contained translation runtime**. All language understanding and generation runs on LangOS-owned inference engines. OpenAI and Anthropic appear only as **API compatibility surfaces** for client migration—not as backend dependencies.

---

## 2. Infrastructure Overview

LangOS is deployed as a **Language Runtime**—a long-lived, horizontally scalable service with optional specialized worker nodes. It is not a batch job, not a serverless function, and not a monolithic ML model server.

```text
                    ┌──────────────────────────────────────┐
                    │           Load Balancer              │
                    │     (nginx / HAProxy / cloud LB)     │
                    └─────────────────┬────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
     ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
     │  LangOS Node 1  │    │  LangOS Node 2  │    │  LangOS Node N  │
     │  (Elixir OTP)   │    │  (Elixir OTP)   │    │  (Elixir OTP)   │
     │  + Rust NIFs    │    │  + Rust NIFs    │    │  + Rust NIFs    │
     └────────┬────────┘    └────────┬────────┘    └────────┬────────┘
              │                       │                       │
              └───────────────────────┼───────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
     ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
     │  Redis Cluster  │    │  Model Storage  │    │  GPU Nodes      │
     │  (L1/L2 cache)  │    │  (owned models) │    │  (optional)     │
     └─────────────────┘    └─────────────────┘    └─────────────────┘
```

No external language API (OpenAI, Anthropic, etc.) is required at runtime. Compatibility endpoints are served by the same LangOS nodes.

---

## 3. Technology Stack

### 3.1 Primary Languages

| Component | Language | Version Target | Role |
|-----------|----------|----------------|------|
| Runtime server | Elixir | 1.16+ | API, orchestration, supervision, concurrency |
| OTP / BEAM | Erlang/OTP | 26+ | Process model, fault tolerance |
| NLP core | Rust | 1.78+ | Tokenizer, parser, graph, inference NIFs |
| ML training | Python | 3.11+ | Offline training, evaluation, data prep |
| NIF bridge | Rustler | latest stable | Elixir ↔ Rust interop |

### 3.2 Key Dependencies

**Elixir:**

| Package | Purpose |
|---------|---------|
| `phoenix` or `plug_cowboy` | HTTP server |
| `jason` | JSON encoding/decoding |
| `rustler` | Rust NIF integration |
| `cachex` or `nebulex` | In-process L1 cache |
| `redix` | Redis client for distributed cache |
| `yaml_elixir` | Configuration loading |
| `telemetry` + `opentelemetry` | Metrics and tracing |
| `ex_doc` | Documentation |

**Rust:**

| Crate | Purpose |
|-------|---------|
| `tokenizers` (HF) | Multilingual tokenization |
| `serde` / `serde_json` | Serialization |
| `petgraph` | Semantic graph |
| `regex` / `lalrpop` | Rule-based parsing |
| `ort` (ONNX Runtime) | LangOS neural engine inference |
| `tiktoken-rs` | Token counting for compatibility API responses |

**Python:**

| Package | Purpose |
|---------|---------|
| `torch` / `transformers` | Model fine-tuning |
| `datasets` | Corpus management |
| ` pydantic` | Training config validation |
| `langos-sdk` (internal) | Evaluation against live API |

---

## 4. Service Topology

### 4.1 Deployment Modes

LangOS supports three deployment profiles:

#### Mode A — Single Node (Development / Edge)

```yaml
deployment: single
services:
  - langos_runtime: all-in-one
engines:
  - rule_engine: enabled
  - neural_engine: enabled
cache: in-memory
compatibility:
  openai: enabled
  anthropic: enabled
```

All pipeline stages run in one BEAM node. Suitable for local development, CI, and offline edge deployment.

#### Mode B — Cluster (Production)

```yaml
deployment: cluster
nodes:
  - role: gateway      # API + routing + cache
    count: 2+
  - role: worker       # pipeline execution
    count: 4+
  - role: inference    # GPU/local model nodes (optional)
    count: 1+
cache: redis_cluster
```

Gateway nodes handle HTTP and cache lookups. Worker nodes execute the pipeline. Inference nodes (optional) host local models with GPU access.

#### Mode C — Distributed Pipeline (High Scale)

```text
API Gateway
    │
    ├── Fast Parser Service      (CPU, RuleEngine, stateless)
    ├── Neural Engine Service    (GPU, LangOS models)
    ├── Semantic Graph Service   (CPU, stateless)
    ├── Generation Service       (GPU or CPU, LangOS models)
    └── Cache Service            (Redis)
```

The gateway decides which sub-services a request needs. Simple commands never touch GPU nodes.

### 4.2 OTP Supervision Tree

```text
LangOS.Application
└── LangOS.Supervisor (one_for_one)
    ├── LangOS.Gateway
    ├── LangOS.Compat.Supervisor
    │   ├── LangOS.Compat.OpenAI
    │   └── LangOS.Compat.Anthropic
    ├── LangOS.Pipeline.Supervisor
    │   ├── LangOS.Pipeline.WorkerPool
    │   └── LangOS.Pipeline.StreamSupervisor
    ├── LangOS.Engine.Supervisor
    │   ├── LangOS.Engine.Rule
    │   ├── LangOS.Engine.Lexical
    │   ├── LangOS.Engine.Syntax
    │   ├── LangOS.Engine.Stat
    │   └── LangOS.Engine.Neural
    ├── LangOS.Cache
    ├── LangOS.LanguagePack.Registry
    └── LangOS.Plugin.Manager
```

Each engine runs under its own supervisor. A neural engine failure does not crash the runtime; the router may fall back to rule/stat engines where possible.

---

## 5. Configuration

### 5.1 Configuration Files

| File | Use |
|------|-----|
| `config/langos.json` | Default runtime config |
| `config/dev.json` | Local development |
| `config/test.json` | Test suite (ports 9573/9574) |

Override with `LANGOS_CONFIG=/path/to/config.json`.

### 5.2 Example (`config/langos.json`)

```json
{
  "runtime": { "name": "langos", "log_level": "info", "max_concurrent_requests": 1000 },
  "server": {
    "http": { "host": "127.0.0.1", "port": 9473 },
    "grpc": { "enabled": true, "port": 9474 }
  },
  "cache": {
    "l1": { "type": "memory", "max_entries": 50000 },
    "l2": { "enabled": false }
  },
  "engines": {
    "rule": { "enabled": true, "patterns_dir": "packs/en/patterns" },
    "syntax": { "enabled": true },
    "lexical": { "enabled": true },
    "stat": { "enabled": true, "model": "models/en/intent.json", "min_confidence": 0.3 },
    "neural": { "enabled": true }
  },
  "routing": {
    "simple_command_max_tokens": 12,
    "simple_command_engine": "rule",
    "stages": {
      "parse": ["rule", "lexical", "syntax", "stat", "neural"],
      "generate": "neural"
    }
  },
  "language_packs": {
    "installed": ["en", "fr", "de", "tr", "rw"],
    "default": "en"
  },
  "plugins": { "dir": "plugins", "installed": ["education-vocab"] },
  "packs_dir": "packs"
}
```

Stat engine loads `models/<locale>/intent.json` per request locale (see [TRAINING.md](./TRAINING.md)).

### 5.3 Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `LANGOS_CONFIG` | No | Path to config file (default: `./config/langos.yaml`) |
| `LANGOS_ENV` | No | `dev` / `staging` / `prod` |
| `REDIS_URL` | If L2 cache enabled | Redis connection string |
| `LANGOS_SECRET_KEY` | Prod | API authentication signing key |
| `LANGOS_API_KEY` | Prod | Key accepted by LangOS (including compatibility endpoints) |

### 5.4 Secrets Management

- Development: `.env` file (gitignored)
- Staging/Production: platform secrets (Fly.io secrets, AWS SSM, Vault)
- Never commit API keys or credentials to the repository

---

## 6. Inference Engine Infrastructure

### 6.1 LangOS Engine Implementations

All engines are owned, hosted, and versioned by LangOS. No runtime calls to OpenAI, Anthropic, or similar language APIs.

| Engine ID | Backend | Deployment | Latency Profile |
|-----------|---------|------------|-----------------|
| `rule` | Elixir + Rust regex/CFG | In-process | ~1–5 ms |
| `stat` | ONNX via Rust NIF | In-process | ~5–20 ms |
| `neural-onnx` | ONNX Runtime NIF | In-process | ~10–100 ms |
| `neural-vllm` | vLLM (LangOS models) | GPU sidecar | ~20–200 ms |
| `neural-llama-cpp` | llama.cpp (LangOS models) | Sidecar or in-process | ~50–500 ms |

During development, neural engines may load open-source base weights (e.g. Qwen, Llama) that LangOS fine-tunes. Production targets fully LangOS-trained model artifacts.

### 6.2 Model Storage

```
models/
├── en/intent.json     # Naive Bayes — 361 classes, 41k examples
├── fr/intent.json     # 28 classes
├── de/intent.json     # 42 classes
├── tr/intent.json     # 217 classes
└── rw/intent.json     # 178 classes
```

Built by `mix patience train --all`. See [TRAINING.md](./TRAINING.md).

English also has `packs/en/lexicon.json` (5,718 entries). Other languages get `packs/<lang>/lexicon.json` from the same train command.

Models are loaded at startup and kept resident in memory. Model files can be:

- Bundled in Docker image (small models)
- Mounted from volume
- Downloaded from object storage on first boot

### 6.3 Engine Health Checks

Each engine implements `health/0`. The runtime exposes:

```
GET /v1/engines/health
```

```json
{
  "rule": "ok",
  "stat": "ok",
  "neural": {"status": "ok", "model": "langos-parse-v1", "latency_ms": 45}
}
```

Unhealthy engines are skipped by the router. Fallback stays within LangOS (e.g. neural → stat → rule)—never to an external language API.

---

## 7. API Compatibility Infrastructure

### 7.1 Purpose

Allow applications (e.g. Duselang) that already use OpenAI or Anthropic SDKs for language work to switch to LangOS by changing `base_url` and API key only.

### 7.2 OpenAI-Compatible Surface

| Setting | Value |
|---------|-------|
| Base URL | `https://<langos-host>/v1` |
| Auth header | `Authorization: Bearer <LANGOS_API_KEY>` |
| Primary endpoint | `POST /v1/chat/completions` |
| Advertised models | `langos-understand-v1`, `langos-express-v1` |

The adapter:

1. Parses the incoming OpenAI request (messages, model, response_format)
2. Invokes `LangOS.understand/1` or `LangOS.express/1` internally
3. Wraps the result in OpenAI chat completion response JSON

### 7.3 Anthropic-Compatible Surface

| Setting | Value |
|---------|-------|
| Base URL | `https://<langos-host>/v1` |
| Auth header | `x-api-key: <LANGOS_API_KEY>` |
| Primary endpoint | `POST /v1/messages` |
| Advertised models | `langos-understand-v1`, `langos-express-v1` |

Same internal pipeline as the OpenAI adapter; response shape follows Anthropic schema.

### 7.4 Compatibility Testing

CI runs contract tests against recorded OpenAI/Anthropic request/response fixtures to ensure SDK clients work unchanged:

```bash
mix test --only compat_openai
mix test --only compat_anthropic
langos compat test-openai --fixture tests/fixtures/openai/
```

---

## 8. Language Pack Infrastructure

### 8.1 Pack Structure

```
packs/en/
├── manifest.yaml           # pack metadata, version, capabilities
├── tokenizer/
│   └── config.json         # Hugging Face tokenizer config or custom
├── patterns/
│   ├── commands.yaml       # rule-based command patterns
│   └── entities.yaml       # entity recognition patterns
├── grammar/
│   └── command.cfg         # optional CFG for fast parser
├── models/                 # optional pack-specific ONNX models
│   └── parse.onnx
├── templates/
│   └── express/            # express path templates
│       ├── missing_fields.yaml
│       ├── success.yaml
│       └── error.yaml
└── tests/
    └── golden.jsonl        # input → expected IR pairs
```

### 8.2 Pack Manifest

```yaml
id: en
version: 1.0.0
name: English
direction: ltr
capabilities:
  - understand
  - express
  - tokenize
tokenizer: tokenizer/config.json
default_locale: en-US
requires:
  kernel: ">=1.0.0"
```

### 8.3 Pack Installation

```bash
# Built-in packs ship with the runtime
langos languages list

# Install additional pack from registry
langos languages install fr --source https://packs.langos.dev/fr/1.0.0

# Install local pack
langos languages install ./packs/rw
```

Packs are loaded dynamically. No recompilation required.

---

## 9. Caching Infrastructure

### 9.1 Cache Architecture

```text
Request
   │
   ▼
L1 Cache (Cachex, in-process, ~1ms)
   │ miss
   ▼
L2 Cache (Redis, ~2-5ms)
   │ miss
   ▼
Pipeline Execution
   │
   ▼
Write-through to L1 + L2
```

### 9.2 Cache Key Design

```
L1: SHA256(text + locale + export_profile + pack_version)
L2: SHA256(unit_text + locale + stage + model_version)
L3: SHA256(ir_predicate_pattern + pack_version)
```

Cache keys include pack and model versions to invalidate automatically on upgrades.

### 9.3 Redis Configuration (Production)

```yaml
redis:
  mode: cluster          # or standalone for small deployments
  nodes:
    - redis://redis-1:6379
    - redis://redis-2:6379
    - redis://redis-3:6379
  pool_size: 20
  max_memory: 2gb
  eviction: allkeys-lru
```

---

## 10. Networking & API Infrastructure

### 10.1 Ports

| Port | Service |
|------|---------|
| 9473 | HTTP API (default) |
| 9474 | gRPC (optional) |
| 9475 | Prometheus metrics |
| 9476 | Health check (lightweight, no auth) |

### 10.2 Authentication

Phase 1: API key in header.

```
Authorization: Bearer lgs_<token>
```

Phase 3: OAuth2 / mTLS for enterprise deployments.

Keys are scoped per application (Duselang, Tembera, etc.) for rate limiting and usage tracking.

### 10.3 Rate Limiting

```yaml
rate_limits:
  default:
    requests_per_minute: 600
    burst: 50
  per_key:
    requests_per_minute: 6000
  per_ip:
    requests_per_minute: 120
```

Implemented at the gateway using Redis token bucket.

### 10.4 Request / Response Limits

| Limit | Value |
|-------|-------|
| Max request body | 10 MB |
| Max text length (sync) | 32,000 tokens |
| Max text length (stream) | 500,000 tokens |
| Max conversation turns in context | 100 |
| Request timeout (sync) | 30 s |
| Request timeout (stream) | 300 s |

---

## 11. Observability

### 11.1 Metrics (Prometheus)

| Metric | Type | Labels |
|--------|------|--------|
| `langos_requests_total` | counter | endpoint, status, language |
| `langos_request_duration_ms` | histogram | endpoint, engine, path |
| `langos_cache_hits_total` | counter | level (l1/l2) |
| `langos_engine_calls_total` | counter | engine, stage, status |
| `langos_engine_latency_ms` | histogram | engine, stage |
| `langos_pipeline_stage_duration_ms` | histogram | stage |
| `langos_active_streams` | gauge | — |
| `langos_units_processed_total` | counter | language |

### 11.2 Structured Logging

All logs are JSON in production:

```json
{
  "timestamp": "2026-07-23T07:47:00Z",
  "level": "info",
  "request_id": "req_abc123",
  "endpoint": "understand",
  "language": "en",
  "engine": "rule",
  "latency_ms": 12,
  "units": 1,
  "cache": "l1_hit"
}
```

User text is **not** logged by default. Opt-in debug mode with PII redaction for development.

### 11.3 Distributed Tracing

OpenTelemetry spans per pipeline stage:

```
understand.request
  ├── gateway.normalize
  ├── cache.lookup
  ├── pipeline.language_detect
  ├── pipeline.split
  ├── pipeline.parse [engine: rule]
  ├── pipeline.extract_entities
  ├── pipeline.build_graph
  └── export.json
```

---

## 12. Build & CI/CD

### 12.1 Build Pipeline

```text
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Rust NIFs  │───►│  Elixir App │───►│  Language   │───►│  Docker     │
│  cargo build│    │  mix compile│    │  Packs      │    │  Image      │
│  --release  │    │             │    │  validate   │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### 12.2 CI Stages

| Stage | Command | Gate |
|-------|---------|------|
| Rust lint + test | `cargo clippy && cargo test` | must pass |
| Elixir lint + test | `mix format --check && mix test` | must pass |
| Python lint + test | `ruff check && pytest` | must pass |
| Schema validation | `ajv validate -s schemas/ -d packs/*/tests/` | must pass |
| Golden tests | `mix test --only golden` | must pass |
| Benchmark regression | `langos benchmark --compare main` | < 10% regression |
| Security scan | `cargo audit`, `mix deps.audit` | no critical |

### 12.3 Docker Image

```dockerfile
# Multi-stage build
FROM rust:1.78 AS rust-builder
WORKDIR /build
COPY crates/ crates/
RUN cargo build --release

FROM elixir:1.16 AS elixir-builder
WORKDIR /build
COPY apps/ apps/
COPY --from=rust-builder /build/target/release/*.so priv/native/
RUN mix deps.get && MIX_ENV=prod mix release

FROM debian:bookworm-slim
COPY --from=elixir-builder /build/_build/prod/rel/langos /app
COPY packs/ /app/packs/
EXPOSE 9473 9475
CMD ["/app/bin/langos", "start"]
```

Variant tags:

- `langos:latest` — full image with default packs
- `langos:slim` — no bundled models (downloads on boot)
- `langos:gpu` — includes CUDA + vLLM sidecar config

---

## 13. Data Infrastructure

### 13.1 Training Data Pipeline (Python, Offline)

```text
Application Logs (opt-in, anonymized)
        │
        ▼
Corpus Collector
        │
        ▼
Annotation Tool  (human text ↔ Semantic IR pairs)
        │
        ▼
Dataset Registry  (versioned, per language)
        │
        ▼
Training Pipeline  (fine-tune per language pack / stage)
        │
        ▼
Evaluation Harness  (golden tests, F1, latency)
        │
        ▼
Model Registry  (versioned ONNX / GGUF artifacts)
        │
        ▼
Pack Release  (manifest + model + patterns)
```

### 13.2 Dataset Format

Training pairs use JSONL:

```json
{"text": "Add Clarissa to Biology A1.", "ir": {"predicate": "assign", "arguments": [...]}, "locale": "en", "source": "duselang"}
{"text": "Ajoutez Clarissa en Biologie.", "ir": {"predicate": "assign", "arguments": [...]}, "locale": "fr", "source": "duselang"}
```

### 13.3 Data Storage

| Data | Storage | Retention |
|------|---------|-----------|
| Training datasets | S3 / MinIO | indefinite, versioned |
| Model artifacts | S3 / MinIO | indefinite, versioned |
| Request logs (metrics only) | Prometheus / Loki | 30 days |
| Request logs (debug, opt-in) | S3 encrypted | 7 days |
| Cache entries | Redis | TTL-based |

No application conversation data is stored by LangOS. Applications own their data.

---

## 14. Development Environment

**Docker is not required for local development.** The default workflow runs LangOS natively on your machine with Elixir, Rust, and Python installed directly. Docker is used for **production deployment** and is **optional** if you want a containerized full stack locally.

| Environment | Docker | Typical use |
|-------------|--------|-------------|
| Local dev (default) | Not required | Day-to-day coding, tests, `langos serve` |
| Local full stack (optional) | Docker Compose | Quick integration test with Redis + neural sidecar |
| Production / staging | Docker (or Fly.io build) | Deployed runtime |

Early development works with **no Docker, no Redis, and no GPU**—the rule engine and in-memory L1 cache are enough for Phase 1.

### 14.1 Prerequisites (native — no Docker)

```bash
# Required
asdf install elixir 1.16.3-otp-26   # or your Elixir install
rustup default stable
python3.11 -m venv .venv && source .venv/bin/activate

# Optional — only when you need them
# Redis (L2 cache): install via package manager, or skip and use in-memory cache only
#   sudo apt install redis-server   # Linux
#   brew install redis              # macOS
#
# Neural engine (Phase 2+): ONNX runs in-process via Rust NIF — no container needed
#   or run vLLM natively if you have GPU drivers installed locally
```

### 14.2 Local Development (native)

```bash
git clone https://github.com/your-org/LangOS.git
cd LangOS

# Install dependencies
mix deps.get
cd crates/langos_nif && cargo build && cd ../..
pip install -e python/

# Run tests
mix test
cargo test
pytest python/

# Start dev server — no Docker
mix phx.server
# or
langos serve --config config/dev.yaml
```

Use `config/dev.yaml` tuned for native dev:

```yaml
# config/dev.yaml — works without Docker, Redis, or GPU
cache:
  l1:
    type: memory
  l2:
    enabled: false          # skip Redis locally

engines:
  rule:
    enabled: true
  stat:
    enabled: true
  neural:
    enabled: false          # enable when models are ready; ONNX NIF needs no Docker

compatibility:
  openai:
    enabled: true
  anthropic:
    enabled: true
```

### 14.3 Optional: Docker Compose (full stack)

Use this only if you want Redis and a neural sidecar without installing them natively. **Skip entirely until you need integration testing.**

```yaml
# docker-compose.yaml — optional, not required for development
services:
  langos:
    build: .
    ports: ["9473:9473", "9475:9475"]
    environment:
      - LANGOS_ENV=dev
      - REDIS_URL=redis://redis:6379
    depends_on: [redis, vllm]

  redis:
    image: redis:7
    ports: ["6379:6379"]

  vllm:
    image: vllm/vllm-openai
    ports: ["8000:8000"]
    volumes: [./models:/models]
    command: ["--model", "/models/parse/langos-parse-v1"]
```

```bash
docker compose up   # optional convenience only
```

---

## 15. Deployment Targets

### 15.1 Recommended Initial Target: Fly.io

LangOS fits Fly.io well:

- Elixir/Erlang runs natively
- Multi-region for latency
- Secrets management built-in
- Scale-to-zero for dev environments

```toml
# fly.toml
app = "langos"
primary_region = "jnb"  # Johannesburg for Rwanda-adjacent latency

[build]
  dockerfile = "Dockerfile"

[[services]]
  internal_port = 9473
  protocol = "tcp"

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

[env]
  LANGOS_ENV = "prod"
```

### 15.2 Alternative Targets

| Platform | Use Case |
|----------|----------|
| **Fly.io** | Primary cloud, multi-region |
| **AWS ECS / EKS** | Enterprise, GPU inference nodes |
| **On-premise** | Offline/air-gapped (Mode A, all LangOS engines local) |
| **Edge device** | Single-node, LangOS neural engine on-device, no Redis |

### 15.3 GPU Inference Node

For Mode C with LangOS neural engines on GPU:

```yaml
inference_node:
  instance: g4dn.xlarge  # or local RTX 4090
  gpu: 1
  services:
    - vllm:
        model: langos-parse-v1
        port: 8000
    - langos:
        engines.neural.base_url: http://vllm:8000
```

LangOS runtime nodes (CPU) call the inference node over HTTP.

---

## 16. Scaling Strategy

### 16.1 Horizontal Scaling

LangOS nodes are **fully stateless** (except in-process L1 cache). Scale by adding nodes behind a load balancer.

| Load Pattern | Action |
|--------------|--------|
| Increased request rate | Add gateway + worker nodes |
| Increased cache miss rate | Expand Redis cluster |
| Increased neural parse demand | Add inference GPU nodes |
| New language | Install language pack (no redeploy) |
| New domain vocabulary | Install plugin (no redeploy) |

### 16.2 BEAM Concurrency Model

Each request runs in an isolated Elixir process. The runtime supports:

- `max_concurrent_requests` per node (default: 1000)
- Dirty NIF scheduling for Rust inference (does not block schedulers)
- Backpressure via `Task.async_stream` with max concurrency

### 16.3 Streaming Backpressure

Long document processing uses `Task.async_stream` per semantic unit with configurable concurrency:

```yaml
pipeline:
  max_parallel_units: 8
  stream_chunk_size: 4   # paragraphs per batch
```

---

## 17. Security

### 17.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| API key theft | Rotate keys, scope per app, rate limit |
| Prompt injection via user text | LangOS does not execute instructions; IR validation rejects executable patterns |
| API key leak | Env vars / secrets manager; LangOS keys only—no vendor keys stored |
| NIF crash | Dirty NIFs + supervisor restarts |
| Large payload DoS | Request size limits, token limits, timeouts |
| PII in logs | No text logging by default; redaction in debug mode |

### 17.2 IR Validation

All engine output passes through `LangOS.IR.validate/1` before export. Invalid IR is rejected—not forwarded to applications.

---

## 18. Testing Infrastructure

### 18.1 Test Layers

| Layer | Tool | Location |
|-------|------|----------|
| Rust unit tests | `cargo test` | `crates/*/tests/` |
| Elixir unit tests | `ExUnit` | `apps/langos/test/` |
| Golden tests (IR accuracy) | `mix test --only golden` | `packs/*/tests/golden.jsonl` |
| Engine integration | `mix test --only engine` | `apps/langos/test/engines/` |
| API compatibility | `mix test --only compat` | `apps/langos/test/compat/` |
| API contract | OpenAPI + Schemathesis | `schemas/` |
| Benchmark | `langos benchmark` | `python/langos_eval/` |
| Load test | k6 | `infra/k6/` |

### 18.2 Golden Test Format

```jsonl
{"input": {"text": "Create student Alice.", "locale": "en"}, "expected": {"predicate": "create", "arguments": [{"role": "target", "label": "student"}, {"role": "name", "value": "Alice"}]}}
```

Golden tests run in CI for every language pack on every PR.

---

## 19. Release Process

### 19.1 Versioning

LangOS follows [Semantic Versioning](https://semver.org/):

- **MAJOR** — breaking IR schema or API changes
- **MINOR** — new language packs, engines, compatibility endpoints
- **PATCH** — bug fixes, model updates within same IR version

IR schema versions independently: `semantic_ir.v1.json`, `semantic_ir.v2.json`.

### 19.2 Release Checklist

1. All CI stages pass
2. Golden test accuracy ≥ baseline for all installed packs
3. Benchmark regression < 10%
4. CHANGELOG updated
5. Language pack manifests versioned
6. Docker image tagged and pushed
7. Migration notes for breaking changes

---

## 20. Cost Model (Estimated)

### 20.1 Development Phase

| Resource | Monthly Estimate |
|----------|-----------------|
| Dev machines | existing hardware |
| Local GPU / CPU inference (dev) | $0 |
| Fly.io staging | $20–50 |
| **Total dev** | **~$20–50/month** |

### 20.2 Production (Initial)

| Resource | Monthly Estimate |
|----------|-----------------|
| 2× LangOS nodes (Fly.io, 1 CPU, 2GB) | $40–80 |
| Redis (Upstash or Fly) | $10–30 |
| GPU inference node (LangOS models) | $200–500 |
| **Total prod (initial)** | **~$250–610/month** |

Costs scale with request volume and GPU usage. Rule-based fast path minimizes neural engine load for common commands. **No per-token fees to external language APIs.**

---

## 21. Implementation Status

Phases 0–3.6 are **complete**. Current focus: Phase 4 (owned ONNX neural models).

| Milestone | Status |
|-----------|--------|
| Elixir runtime + 5 engines | ✓ |
| Semantic IR v1.2 graph | ✓ |
| 5 language packs (en, fr, de, tr, rw) | ✓ |
| Per-language intent models | ✓ |
| OpenAI + Anthropic compat APIs | ✓ |
| gRPC + MCP + document streaming | ✓ |
| `patience train` / `setup` / `install` CLI | ✓ |
| Remote pack download | planned |
| ONNX neural engine | Phase 4 |

---

## 22. Related Documents

- [ARCHITECTURE.md](./ARCHITECTURE.md) — System design, Semantic IR, phases
- [TRAINING.md](./TRAINING.md) — Build lexicon + intent models
- [MODEL_vs_PACK.md](./MODEL_vs_PACK.md) — `packs/` vs `models/`
- [ENGINE_SPEC.md](./ENGINE_SPEC.md) — Engine behaviour contract
- [EVOLUTION.md](./EVOLUTION.md) — Post-v1.0 growth strategy
- [LANGUAGE_PACK_GUIDE.md](./LANGUAGE_PACK_GUIDE.md) — Add a new language
- `schemas/semantic_ir.v1.2.json` — IR schema
- `schemas/openapi.yaml` — HTTP API spec

---

## 23. Glossary

| Term | Definition |
|------|------------|
| **BEAM** | Erlang VM hosting Elixir processes |
| **NIF** | Native Implemented Function (Rust compiled into BEAM) |
| **Language Pack** | Installable module for one human language |
| **Inference Engine** | LangOS-owned component: Rule, Lexical, Syntax, Stat, Neural |
| **API Compatibility Layer** | OpenAI/Anthropic-shaped endpoints; internal pipeline only |
| **Golden Test** | Fixed input → expected IR test pair |
| **Fast Path** | Rule/statistical route bypassing neural models |
| **Mode A/B/C** | Single node / cluster / distributed deployment profiles |
