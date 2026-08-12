# Decisions

An ADR-style log of the "why" behind key infrastructure choices — context, decision, and tradeoff for each. Most of these were made and documented in the private application repo's own Terraform/Helm comments and READMEs, written at the time (often mid-incident); this page distills them for anyone without access to that repo. Where something is still genuinely unresolved, it's marked open rather than papered over — see [Roadmap](roadmap.md) for what happens to those next.

## Format

Each entry below follows:

- **Context** — what problem or constraint prompted the decision.
- **Decision** — what was chosen.
- **Tradeoff** — what was given up, and why it was an acceptable cost.

## Entries

### Cluster / compute platform: GKE Standard, not Autopilot, not Cloud Run

- **Context**: production needs somewhere to run five long-lived processes (API, nginx, worker, cache, tunnel client). Serverless (Cloud Run), a managed autopilot cluster (GKE Autopilot), and a manually-run cluster (GKE Standard) were all realistic options for a workload this small.
- **Decision**: GKE **Standard**, zonal, one manually-sized, autoscaled node pool. Deliberately not Autopilot — the stated reason (in `infrastructure/gcp/README.md`) is that node-pool management is itself something to learn here, not just app deployment.
- **Tradeoff**: this is the most expensive and highest-ops-burden of the three realistic options. Cloud Run would very likely be cheaper and near-zero-ops for this traffic level — see the [comparison table in Cost Analysis](cost-analysis.md#compute-platform-comparison). The extra ~$40–50/month and the operational surface (node pools, Helm, `kubectl`, NetworkPolicy, cluster upgrades) is accepted on purpose, in exchange for hands-on Kubernetes operational experience that Cloud Run wouldn't provide. This is a portfolio/skill-building tradeoff, not a technical requirement of the app itself — worth saying plainly rather than presenting GKE as the "obviously correct" choice.

### GKE node sizing: e2-standard-2, not e2-medium

- **Context**: the node pool went through three sizes in quick succession — e2-small → e2-medium → e2-standard-2 — after two real "Insufficient cpu" incidents where the worker, then the backend, sat `Pending` for 100+ minutes each because the pool couldn't schedule them.
- **Decision**: `e2-standard-2` (non-shared-core). The root cause turned out to be that `e2-small`/`e2-medium` are both *shared-core* machine types, and GKE reserves a flat ~1060m CPU per node for system DaemonSets (calico, kube-dns, fluentbit, the Workload Identity metadata server) regardless of the node's nominal vCPU count — confirmed live at exactly 940m allocatable out of a nominal 2000m on `e2-medium`. Moving to memory (2GB → 4GB) with the e2-medium step never touched that ceiling; only moving off shared-core did.
- **Tradeoff**: `e2-standard-2` costs more per node than `e2-medium`. But `e2-medium` was a more expensive way to still be broken, not a cheaper working option — the real fix was changing machine family, not size. Applying this kind of node-pool field change also has its own hazard: two of the underlying Terraform provider fields here (`workload_metadata_config`, and machine-type changes in general) are known to force-replace or silently no-op the whole pool instead of doing GKE's own in-place rolling update — the working pattern documented in `gke.tf` is to make the change via `gcloud` first, then confirm `terraform plan` shows no diff before ever applying.

### Redis: in-cluster container, not Memorystore

- **Context**: Redis is needed for two things — the Symfony cache pool and the Messenger transport — and GCP's managed option (Memorystore) exists as an alternative to running it as just another pod.
- **Decision**: a plain, single-replica Redis container inside the cluster, not Memorystore.
- **Tradeoff**: Memorystore's smallest Basic-tier instance costs roughly as much per month as the entire node pool at its 1-node steady state — disproportionate for something serving as a cache plus a queue transport at this traffic level. The cost saved comes directly at the expense of durability: no managed failover, and — see the next entry — no persistence at all today.

### Redis: cache and queue on one instance, with no persistence in production

- **Context**: one Redis instance serves both a loss-tolerant cache (`cache.app`, `cache.auth_sessions`) and the Messenger `async` transport carrying every AI-pipeline job. `symfony/redis-messenger` is Streams-based (`XADD`/`XREADGROUP` with consumer groups), not plain pub/sub, so message delivery itself has ack/retry semantics rather than being fire-and-forget — that much is a genuine strength of the current setup, not an open question.
- **Decision**: run it anyway, as a single pod, with **no PersistentVolumeClaim** (`infrastructure/gcp/helm/sutras/templates/redis-deployment.yaml` mounts nothing — it's in-memory only, unlike the equivalent Docker Compose service, which does persist to a volume).
- **Tradeoff**: this is the one infrastructure gap in this whole system worth calling out clearly. Redis Streams' ack/retry semantics only protect against *consumer* failure, not against *Redis itself* losing its data — and the pod restarts routinely, because the cluster autoscaler scales the node pool between 1 and 3 nodes as load changes, which can reschedule the Redis pod. When that happens, both the cache (expected, fine) and any queued-but-not-yet-consumed pipeline job (not fine — silently lost, no user-visible error, no retry) disappear together. This is accepted today because traffic is low enough that the exposure window is small, not because it's actually resolved — see [Roadmap](roadmap.md#now).

### Ingress path: Cloudflare Tunnel + Workers, not a GCP load balancer

- **Context**: the API and frontend both need a public HTTPS endpoint. A GKE Ingress backed by a GCP external HTTP(S) Load Balancer is the "default" answer; Cloudflare was already in use for DNS.
- **Decision**: the API is reached via a **Cloudflare Tunnel** — an outbound-only `cloudflared` pod, no GKE Ingress, no static IP, no GCP forwarding rule. The frontend isn't deployed to GKE at all; the built static bundle ships straight to **Cloudflare Workers Static Assets** (not Cloudflare Pages), via Terraform applying the built `frontend/dist/` directory directly.
- **Tradeoff**: a GCP external HTTP(S) Load Balancer alone runs close to $20/month before any traffic; this setup avoids that entirely, and TLS termination at Cloudflare's edge is effectively free. In exchange, production availability now has a hard dependency on Cloudflare's edge and on the single `cloudflared` pod staying healthy — there's no non-Cloudflare fallback path to the API at all. It's a single point of failure introduced deliberately for its cost profile.

### How pipeline completion reaches the client: still unresolved

- **Context**: an entry (`Axiom` in the codebase) is saved synchronously but finishes its four-stage AI pipeline asynchronously, often seconds later.
- **Decision**: none yet, and this isn't a documentation gap — it's confirmed absent in the frontend source. There is no polling loop, `EventSource`/SSE, or `WebSocket` client anywhere in `frontend/src/`; the only `setInterval` in the codebase belongs to an unrelated rotating-quote widget. A user finds out an entry finished only by reloading or revisiting the page (or noticing the in-app notification on their next page load).
- **Tradeoff**: not choosing yet is itself a choice — it keeps the frontend simpler and avoids picking a push mechanism before there's real evidence of how much it matters to users. The cost is a genuinely worse experience today: "processing" can sit stale on screen indefinitely with no signal that it's done. See [Roadmap](roadmap.md#next) — this is a "next," not a "now," specifically because it's a UX gap rather than a reliability or cost risk.

### Self-hosted AI models: prototyped, not wired in

- **Context**: every pipeline stage calls the Claude API today, at low but non-zero cost (~$5/month at current volume). A self-hosted alternative was worth exploring before that cost becomes a real constraint.
- **Decision**: three standalone FastAPI + llama-cpp-python services exist (`ai-server/`), each running a small open-weight model (`Qwen2.5-1.5B-Instruct`, quantized GGUF, CPU-only) with a system prompt mirroring the Claude provider's prompts — but nothing in the backend calls them. The AI pipeline's `CorrectionProvider`/`ContentValidationProvider` ports (see [Architecture](architecture.md#the-ai-pipeline)) already make this a swap-in, not a rewrite, whenever it's needed.
- **Tradeoff**: building it now, ahead of need, cost real time that could've gone into product features — but the alternative (hitting an unacceptable Claude bill with no fallback already built) is worse. This is deliberately "ahead of the product surface," the same pattern called out in [Architecture](architecture.md#whats-next).

### Dual-cloud split: AWS for UAT, GCP for production — and AWS only runs on demand

- **Context**: wanted both a real pre-production gate before a release reaches users, and hands-on breadth across two major clouds — without paying for two always-on environments on a $100/month budget.
- **Decision**: AWS (`infrastructure/aws/`) hosts UAT — VPC, ECS Fargate, RDS, ElastiCache, ALB, all Terraform-provisioned — but it is applied and destroyed by hand, one `terraform apply`/`terraform destroy` at a time, for a testing session, not left running. GCP hosts the always-on production environment and is the only piece deployed automatically (see [Deployment](deployment.md#release-process)).
- **Tradeoff**: UAT can't be shared as a live link on demand — someone wanting to see it needs it stood up first — and its release path is entirely manual, with no CI workflow wired to it. That's accepted because UAT's job here is a pre-release check, not a demo environment, and running it continuously would be the single most expensive piece of this whole system: see the [AWS estimate in Cost Analysis](cost-analysis.md#aws-uat-if-left-running-247), which is why real spend on it to date is a few dollars, not a monthly bill.

### AWS security posture: "Phase 1" now, "Phase 2" deliberately deferred

- **Context**: `infrastructure/aws/README.md` documents this split explicitly — Phase 1 ("standard hardening": private subnets, least-privilege security groups, encryption at rest, secrets in SSM, HTTPS-only ALB, VPC Flow Logs) is built; Phase 2 (AWS WAF, restricting the ALB to known IP ranges instead of `0.0.0.0/0`, GuardDuty) is written down but not started.
- **Decision**: ship Phase 1 only, and write Phase 2 down in the repo specifically so it isn't forgotten — not because it's scheduled.
- **Tradeoff**: UAT is currently reachable from the entire internet with no WAF in front of it. Acceptable for a non-public, testing-only environment that's usually not even running (see the entry above) — would not be acceptable if UAT traffic or visibility grew.

### Single replica, zero-surge rolling updates: brief downtime is accepted

- **Context**: `backend`, `nginx`, and `worker` each run `replicaCount: 1` with `maxSurge: 0, maxUnavailable: 1` in the Helm chart.
- **Decision**: accept that every deploy briefly runs zero pods of each Deployment while the old pod terminates and the new one starts and passes its readiness probe.
- **Tradeoff**: this is the cheapest possible topology — paying for exactly one pod of each component — and it sidesteps a subtler correctness problem: running two `worker` replicas without any de-duplication or locking on the pipeline could double-process the same entry. The cost is real, if brief (roughly the readiness-probe delay plus image pull time), user-visible downtime on every release. Acceptable today with no uptime SLA and low traffic; the fix (`replicaCount: 2` + a PodDisruptionBudget, once the double-processing risk is separately handled) is a [Roadmap](roadmap.md#next) item, not urgent.

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) — Michael Nygard's original write-up; the source of the context/decision/tradeoff format this log follows.
- [adr.github.io](https://adr.github.io/) — community index of ADR templates and tooling, useful if this ever needs to grow past a single flat file.
