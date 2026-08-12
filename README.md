# sutras-playbook

<img src="docs/assets/logo.svg" width="64" height="64" alt="Sutras logo" align="left" />

Architecture and operations case study for [Sutras](https://sutras.dev), a production SaaS app. Real cost data, decision rationale, and scaling strategy — no source code, just the thinking behind the systems.

<br clear="left" />

## What is Sutras

Sutras is a personal knowledge base for micro-learning: a place to record, in a sentence or two, what you actually learned today. Saving isn't the finish line — writing the explanation is. Each entry is a single learned fact (not a bookmark or a topic label), and an AI pipeline corrects and tightens the wording so it reads well later. Entries are organized under tags, each acting like its own "book," and the app surfaces insights (streaks, active/quiet topics) and suggestions for what to learn next.

**Live app:**

| | |
|---|---|
| Marketing site | [sutras.dev](https://sutras.dev) |
| App | [app.sutras.dev](https://app.sutras.dev) |
| API | [api.sutras.dev](https://api.sutras.dev) |

## Contents

- [Architecture](docs/architecture.md) — system structure, backend/frontend layers, the AI processing pipeline.
- [Deployment](docs/deployment.md) — environments, cloud providers, release process.
- [Operations](docs/operations.md) — runbook: deploys, rollbacks, health checks, alerts.
- [Cost Analysis](docs/cost-analysis.md) — what it actually costs to run.
- [Scaling](docs/scaling.md) — current limits and what changes as load grows.
- [Decisions](docs/decisions.md) — an ADR-style log of the "why" behind key infra choices.
- [Roadmap](docs/roadmap.md) — every open gap, prioritized: now, next, later, and deliberately not planned.

Docs are also published as a browsable site via [MkDocs Material](https://squidfunk.github.io/mkdocs-material/). Run `make docs-serve` (Docker, no local Python needed) to view them at `http://localhost:8000` with navigation and search.

---

Maintained by Sharmilan — [@sharmilanAmpi](https://github.com/sharmilanAmpi)
