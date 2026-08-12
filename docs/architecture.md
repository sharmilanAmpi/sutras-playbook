# Architecture

Sutras is a small, deliberately boring system in the places that don't matter, and careful in the one place that does: the pipeline that turns a rough thought into something worth keeping.

## Overview

The product is two applications talking to one API: a React SPA where you write and browse entries, and a Symfony backend that owns the data and orchestrates an asynchronous AI pipeline over everything you save. Postgres holds the durable data; Redis does double duty as cache and message transport for a background worker that runs the AI pipeline off the request path, so saving an entry is instant and the "thinking" happens after.

```mermaid
flowchart LR
    User(("Browser")) --> SPA["React SPA"]
    SPA -->|REST API| API["Symfony API"]
    API --> DB[("PostgreSQL")]
    API -->|enqueue| Queue(("Redis\nqueue + cache"))
    Queue --> Worker["Async worker\n(AI pipeline)"]
    Worker -->|today| Claude[("Claude API")]
    Worker -.->|self-hosted experiment| Local["Open-weight model\n(cost / resilience)"]
```

## Design philosophy: ports & adapters

Both apps are built hexagonal — business rules live in a framework-free core (`domain` + `application`), and everything that talks to the outside world (HTTP controllers, the database, the UI framework, the AI provider) is an adapter plugged in at the edge through an interface. The core never imports an adapter; it depends on a port, and an adapter implements it.

```mermaid
flowchart LR
    subgraph Driving["Driving side"]
        A["HTTP / UI"]
    end
    subgraph Core["Core"]
        direction TB
        AP["Application\n(use cases)"] --> DM["Domain\n(rules)"]
    end
    subgraph Driven["Driven side"]
        B["Database / External APIs"]
    end
    A -->|calls| AP
    AP -.->|port| B
```

This isn't architecture for its own sake — it buys three things that matter for a product still finding its shape:

- **The core is testable without booting anything.** Business rules are plain classes, tested directly, no framework, no HTTP, no database.
- **Adapters are swappable without a rewrite.** The AI provider behind the pipeline is a port, not a hardcoded call — see below. So is persistence, so is the delivery mechanism.
- **A future split stays mechanical.** If the frontend and backend ever need to move into separate repos, or a mobile client joins the React SPA, the boundary is already drawn.

## The AI pipeline

This is the part of the system actually worth showing. Every entry a user writes goes through four sequential, asynchronous passes before it's considered finished:

1. **Content-safety validation** — a gate, not a suggestion. If this fails or errors, the entry is rejected outright and never proceeds.
2. **Grammar & wording correction** — tightens the raw thought into something readable.
3. **Technical-accuracy correction** — a second pass focused on correctness, not just prose.
4. **Simplification** — makes sure the final entry is still readable months later, out of context.

```mermaid
flowchart LR
    Save["Entry saved"] --> Validate["Validate"]
    Validate -->|unsafe| Review["Held back +\nrouted to human review"]
    Validate -->|safe| Correct["Correct"]
    Correct --> Context["Context-correct"]
    Context --> Simplify["Simplify"]
    Simplify --> Done["Published"]
```

Each stage only runs if the previous one succeeded — a failure after validation just stops the chain, no partial or corrupted output ever reaches the user. Every attempt, at every stage, is written to an append-only audit log, so both the entry's owner and a curator can see exactly what happened and why. Content that fails validation isn't silently dropped: it's flagged, the entry's author is protected from publishing something unsafe, and a curator is notified and can review and clear it.

The pipeline runs against the Claude API today. Because the AI step sits behind a port rather than a direct dependency, there's a self-hosted alternative already being prototyped — small open-weight models running the same four prompts on commodity CPU hardware — as a path to lower per-entry cost and less single-vendor exposure as usage grows, without touching anything upstream of that port.

## How data actually travels

The diagrams above show the boxes; this is the sequence between them for the one flow that matters — writing an entry.

```mermaid
sequenceDiagram
    participant U as Browser
    participant S as SPA
    participant A as Symfony API
    participant D as PostgreSQL
    participant R as Redis
    participant W as Async worker

    U->>S: Write entry, submit
    S->>A: POST /entries
    A->>D: INSERT entry (status: pending)
    A->>R: Enqueue pipeline job
    A-->>S: 201 Created (status: pending)
    S-->>U: Entry shown as "processing"

    R->>W: Deliver job
    activate W
    loop Validate -> Correct -> Context-correct -> Simplify
        W->>D: Persist stage result + audit log entry
    end
    W->>D: Update entry (status: published)
    deactivate W

    Note over S,U: TODO — how does the client learn the entry<br/>finished? Poll on an interval, SSE/WebSocket,<br/>or a Redis pub/sub push?
```

> **Open question:** the request path (API to Postgres) is synchronous and easy to reason about. The response path back to the user once the worker finishes is not documented anywhere yet — pick a mechanism and record it in [Decisions](decisions.md).

## Redis: cache and queue, one instance

The overview above says Redis "does double duty as cache and message transport," but a cache and a queue want opposite things from the same store: a cache is fine to lose (TTL, eviction under memory pressure); a queued pipeline job is not — losing one silently drops an entry mid-pipeline with no user-visible error.

```mermaid
flowchart LR
    subgraph RedisBox["Redis — one instance, two contracts"]
        direction TB
        Cache["Cache\nTODO: what's cached — sessions? read models?\nTTL-based, loss is acceptable"]
        Queue["Queue transport\npipeline jobs\nTODO: must survive a restart — does it?"]
    end
    API["Symfony API"] -->|cache read/write| Cache
    API -->|enqueue job| Queue
    Worker["Async worker"] -->|consume + ack| Queue
```

> **Open question, unresolved by this doc:** is the queue side backed by something durable (Redis Streams, or a Symfony Messenger transport with persistence) with ack/retry semantics, or is it plain pub/sub — which is fire-and-forget and drops messages if the worker is down when they're published? That answer decides whether Redis is a permanent piece of this architecture or a placeholder to swap for a dedicated broker as volume grows. Record the decision in [Decisions](decisions.md#redis-cache-and-queue-on-one-instance).

## Component view: backend

The hexagonal diagram earlier is the pattern; this is where the pattern should map onto the actual Symfony modules. Placeholder below — fill in real class/namespace names.

```mermaid
flowchart TB
    subgraph Driving["Driving adapters"]
        HTTP["HTTP controllers"]
        CLI["Worker entry point\n(Messenger consumer)"]
    end
    subgraph Application["Application — use cases"]
        UC["TODO: e.g. CreateEntry, RunPipelineStage,\nReviewFlaggedEntry"]
    end
    subgraph Domain["Domain"]
        Dom["TODO: e.g. Entry, PipelineRun,\nValidationPolicy, AuditLog"]
    end
    subgraph Driven["Driven adapters"]
        Repo["TODO: persistence adapter (Doctrine)"]
        AIPort["AI provider port"]
        Claude["Claude adapter"]
        Local["Local model adapter"]
    end
    HTTP --> UC
    CLI --> UC
    UC --> Dom
    UC -.-> Repo
    UC -.-> AIPort
    AIPort --> Claude
    AIPort --> Local
```

## Component view: frontend

Same gap on the SPA side — and the earlier "both apps are built hexagonal" claim is untested here unless the split actually shows up in the frontend too. Placeholder below, drawn the same shape as the backend one on purpose — if the real SPA doesn't map cleanly onto driving/application/domain/driven, that claim needs correcting, not the diagram.

```mermaid
flowchart TB
    subgraph Driving["Driving side — UI"]
        Views["TODO: views/components —\nentry list, entry editor, curator review queue"]
    end
    subgraph AppCore["Application — hooks / use-cases"]
        Hooks["TODO: e.g. useCreateEntry, useEntryStatus,\nuseCuratorQueue"]
    end
    subgraph Domain["Domain — client-side rules"]
        DomFE["TODO: e.g. entry status transitions,\nvalidation-error presentation rules"]
    end
    subgraph Driven["Driven side — adapters"]
        APIClient["API client adapter (REST)"]
        Notif["Notification adapter —\nTODO: poll timer? SSE/WebSocket client?"]
    end
    Views --> Hooks
    Hooks --> DomFE
    Hooks -.->|port| APIClient
    Hooks -.->|port| Notif
    APIClient -->|REST| Backend["Symfony API"]
```

The `Notif` adapter is the same open question flagged in [How data actually travels](#how-data-actually-travels) — whatever mechanism gets chosen there is what lives behind this port.

## Why it's built this way

The interesting engineering problem here isn't CRUD — it's turning unstructured, sometimes-unsafe user input into something trustworthy enough to publish, without a human in the loop on the happy path, while keeping a human very much in the loop the moment something looks wrong. That tradeoff — automate aggressively, but fail closed and leave an audit trail — is the actual design decision behind everything above.

## What's next

The architecture is intentionally ahead of the product surface: the pipeline, the audit trail, and the review tooling are built for a scale of usage the product doesn't have yet. Current focus is less on the plumbing and more on the parts users see day to day — a browsing experience that makes a growing library of entries feel navigable, and lightweight nudges toward what to learn next. See [Decisions](decisions.md) for the specific infrastructure tradeoffs behind this, and [Scaling](scaling.md) for what changes as usage grows.

## References

Concepts used throughout this page, for anyone new to them:

- [C4 model](https://c4model.com/) — the Context → Container → Component → Code leveling this page loosely follows (Overview = Context/Container, the Component-view sections = Component).
- [arc42](https://arc42.org/) — the broader template this whole `docs/` split (architecture, decisions, deployment, scaling, operations, cost) is modeled after.
- [Hexagonal Architecture (Ports & Adapters)](https://alistair.cockburn.us/hexagonal-architecture/) — Alistair Cockburn's original write-up; the source of the driving/core/driven vocabulary used in the design-philosophy and component diagrams.
- [Architecture Decision Records](https://adr.github.io/) — the format `decisions.md` follows (context / decision / tradeoff per entry).
