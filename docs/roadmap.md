# Roadmap

Everything on this site that's flagged as an open gap, incident, or deliberate deferral, collected in one place with a rough priority order. This is an infrastructure/architecture roadmap specifically — it doesn't duplicate the private app repo's own product-feature backlog, which lives closer to the code than a case-study site should.

"Now" means cheap and worth doing regardless of traffic. "Next" means needed once real usage shows up, not yet urgent. "Later" means a real tradeoff being deliberately deferred, revisited if a specific trigger condition is hit. "Not planned" means considered and rejected for this project's scale, not merely unstarted.

## Now

Cheap fixes, or currently-live risks with no offsetting benefit — do these regardless of what happens with traffic.

- **Give the in-cluster Redis pod a PersistentVolumeClaim.** Right now a pod restart (which the node autoscaler triggers routinely) silently drops both the cache and any queued-but-unconsumed pipeline job. A PVC is a small, essentially free change that closes an active data-loss path. See [Decisions](decisions.md#redis-cache-and-queue-on-one-instance-with-no-persistence-in-production).
- **Verify the AWS RDS backup retention is actually set.** `rds.tf` doesn't set `backup_retention_period` explicitly — worth confirming it isn't silently defaulting to 0 (backups disabled) before UAT is trusted with anything that would hurt to lose.
- **Restore-test the Cloud SQL automated backup at least once.** "Backups enabled" (`db.tf`) has never been confirmed restorable — an untested backup is a hope, not a plan.
- **Fix the release-workflow tag-trigger condition.** Both `backend-release.yml` and `frontend-release.yml` currently trigger on `startsWith(github.event.release.tag_name, 'v')`, but the documented tag scheme (`infrastructure/gcp/README.md`, `deployment.md`) is `backend-vX.Y.Z` / `frontend-vX.Y.Z` — which doesn't start with `v`. Worth confirming the actual tags being published match what the condition expects, since as written it looks like it could match both workflows on the same tag, or neither.

## Next

Needed once real usage shows up — not urgent today, but the next things to reach for.

- **A push mechanism for pipeline completion** — start with a simple poll interval, revisit SSE/WebSocket if polling proves too chatty. The single biggest user-visible gap on this whole site: see [Decisions](decisions.md#how-pipeline-completion-reaches-the-client-still-unresolved).
- **Wire the production Playwright smoke suite into the release pipeline** as an automatic post-deploy health gate, with a rollback on failure — today it's a manual, human-triggered check, and releases have no automated rollback at all. See [Operations](operations.md#rolling-back).
- **`replicaCount: 2` + a PodDisruptionBudget** for `backend`/`nginx`, once double-processing risk on `worker` is separately guarded against (e.g. an idempotency key per entry+stage, or a distributed lock). Removes both the per-deploy downtime and the single-pod-failure blast radius. See [Decisions](decisions.md#single-replica-zero-surge-rolling-updates-brief-downtime-is-accepted).
- **Basic error tracking / structured log aggregation** beyond the two uptime checks — today a failure that doesn't also take down `/health` is invisible. Doesn't need to be expensive (Sentry's free tier or Cloud Logging-based alerting would both close most of this gap).
- **A HorizontalPodAutoscaler for `backend`**, once real traffic data justifies pod-level autoscaling — today only the node pool scales, never individual pods.

## Later

Real tradeoffs, deliberately deferred — revisit if the trigger condition next to each one actually happens.

- **AWS Phase 2 security** (WAF, restricting the ALB security group off `0.0.0.0/0`, GuardDuty) — already written down as intentionally deferred in `infrastructure/aws/README.md`. Trigger: UAT becomes more visible or more continuously running than it is today. See [Decisions](decisions.md#aws-security-posture-phase-1-now-phase-2-deliberately-deferred).
- **Cloud SQL HA (`availability_type = REGIONAL`) and/or a read replica / connection pooler (PgBouncer).** Trigger: connection exhaustion or query latency becomes the actual bottleneck, not CPU — see [Scaling](scaling.md#what-breaks-first).
- **Reconsider Memorystore over in-cluster Redis.** Trigger: the queue's reliability genuinely needs to be higher than "best effort," and the cost premium (roughly a node's worth of spend) becomes justifiable. See [Decisions](decisions.md#redis-in-cluster-container-not-memorystore).
- **Wire the self-hosted `ai-server/` models in** as a real `CorrectionProvider` adapter (or a hybrid provider that routes between it and Claude). Trigger: Claude API cost, not infrastructure cost, becomes the binding constraint. See [Decisions](decisions.md#self-hosted-ai-models-prototyped-not-wired-in).
- **A regional (not zonal) GKE cluster.** Trigger: uptime genuinely matters more than the added node-pool cost — today a zone-level GCP incident takes the whole app down, and that's accepted.

## Not planned

Considered and deliberately rejected for this project's current scale, not simply unstarted.

- **Multi-region or multi-cloud active-active.** No product need at this scale, and would cost a multiple of the entire $100/month budget on its own.
- **Moving AWS/UAT onto EKS to mirror GKE.** The point of running UAT on AWS is breadth across a different compute model (ECS Fargate), not a second copy of the Kubernetes setup — and EKS's fixed control-plane cost doesn't fit an environment that's meant to be spun up and torn down, not always-on.
