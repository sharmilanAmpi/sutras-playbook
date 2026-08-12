# Decisions

An ADR-style log of the "why" behind key infrastructure choices — context, decision, and tradeoff for each.

## Format

Each entry below should follow:

- **Context** — what problem or constraint prompted the decision.
- **Decision** — what was chosen.
- **Tradeoff** — what was given up, and why it was an acceptable cost.

## Entries

### > TODO: e.g. "Why GKE, not a serverless container platform"

- **Context**:
- **Decision**:
- **Tradeoff**:

### > TODO: e.g. "Why Redis in-cluster, not a managed cache"

- **Context**:
- **Decision**:
- **Tradeoff**:

### > TODO: e.g. "Why a tunnel into the cluster, not a public load balancer"

- **Context**:
- **Decision**:
- **Tradeoff**:

### Redis: cache and queue on one instance

- **Context**: raised in [Architecture](architecture.md#redis-cache-and-queue-one-instance) — one Redis instance serves both a cache (loss-tolerant) and the pipeline job queue (loss-sensitive). Need to record whether the queue side is durable (Streams / a persistent Messenger transport with ack+retry) or plain pub/sub, and what happens to an in-flight job if Redis restarts.
- **Decision**:
- **Tradeoff**:

### > TODO: "How pipeline completion reaches the client"

- **Context**: raised in [Architecture](architecture.md#how-data-actually-travels) — an entry is saved synchronously but finishes processing asynchronously. Undocumented: poll on an interval, SSE/WebSocket push, or Redis pub/sub driving a push to the client.
- **Decision**:
- **Tradeoff**:
