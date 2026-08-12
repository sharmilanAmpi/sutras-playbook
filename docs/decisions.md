# Decisions

An ADR-style log of the "why" behind key infrastructure choices — context, decision, and tradeoff for each.

## Format

Each entry below should follow:

- **Context** — what problem or constraint prompted the decision.
- **Decision** — what was chosen.
- **Tradeoff** — what was given up, and why it was an acceptable cost.

## Entries

### Cluster / compute platform

- **Context**: raised in [Deployment](deployment.md#deployment-view) — the deployment view has an unresolved node, `TODO: cluster — managed k8s / self-hosted / other?`. Whatever's chosen also shapes the rollout mechanism in that doc's release-process diagram.
- **Decision**:
- **Tradeoff**:

### Redis: in-cluster vs. managed

- **Context**: raised in [Deployment](deployment.md#deployment-view) — Redis's placement (in-cluster pod vs. a managed cache service). Related to but distinct from [cache-and-queue-on-one-instance](#redis-cache-and-queue-on-one-instance) below: a managed service can change the durability answer to that question for free, self-hosted-in-cluster doesn't.
- **Decision**:
- **Tradeoff**:

### Ingress path: tunnel vs. public load balancer

- **Context**: raised in [Deployment](deployment.md#deployment-view) — the `Ingress` node is undocumented. Affects DNS/CDN setup and the attack surface of the production environment.
- **Decision**:
- **Tradeoff**:

### Redis: cache and queue on one instance

- **Context**: raised in [Architecture](architecture.md#redis-cache-and-queue-one-instance) — one Redis instance serves both a cache (loss-tolerant) and the pipeline job queue (loss-sensitive). Need to record whether the queue side is durable (Streams / a persistent Messenger transport with ack+retry) or plain pub/sub, and what happens to an in-flight job if Redis restarts.
- **Decision**:
- **Tradeoff**:

### How pipeline completion reaches the client

- **Context**: raised in [Architecture](architecture.md#how-data-actually-travels) — an entry is saved synchronously but finishes processing asynchronously. Undocumented: poll on an interval, SSE/WebSocket push, or Redis pub/sub driving a push to the client.
- **Decision**:
- **Tradeoff**:

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) — Michael Nygard's original write-up; the source of the context/decision/tradeoff format this log follows.
- [adr.github.io](https://adr.github.io/) — community index of ADR templates and tooling, useful if this ever needs to grow past a single flat file.
