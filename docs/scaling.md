# Scaling

How Sutras scales today, and what changes as load grows. Short version: scaling exists at exactly one level (the GKE node pool) and nowhere else — every workload is a single, fixed-replica pod, and the database has no read path beyond the primary. That's not an oversight so much as a direct consequence of the [$100/month budget](cost-analysis.md); this page is about where that starts to show.

## Current limits

| Layer | Current bound | Set where |
|---|---|---|
| GKE node pool | Autoscaled, **min 1, max 3** nodes (`e2-standard-2`, 2 vCPU/8GB each) | `infrastructure/gcp/terraform/gke.tf` |
| Backend / nginx / worker pods | Fixed at **1 replica each** — no HorizontalPodAutoscaler exists | `infrastructure/gcp/helm/sutras/values.yaml` |
| Redis | 1 replica, in-memory only, no persistence | same |
| Cloud SQL | `db-f1-micro`, zonal (no HA), no read replica | `infrastructure/gcp/terraform/db.tf` |
| Rolling deploys | `maxSurge: 0` — every release briefly runs 0 pods of that Deployment | Helm chart deployment templates |

The node pool's `min_node_count = 1` is a deliberate, documented tradeoff, not an oversight: on `e2-standard-2`'s real ~1930m allocatable CPU, one node comfortably holds the whole app (~450–550m) with headroom, and at the CPU utilization actually observed in production (9–12%), the autoscaler is expected to sit at 1 node most of the time. The tradeoff accepted along with that: at 1 node, a single node failure (or its own auto-repair cycle) is a full-cluster outage, since there's nothing else to fail over to at either the node or the pod level.

## What breaks first

**The GKE node pool's schedulable CPU — and this isn't hypothetical, it already happened twice.** Before the pool was resized to `e2-standard-2`, both the `worker` and (separately) the `backend` Deployment got stuck `Pending` for 100+ minutes each on "Insufficient cpu" — because shared-core node types (`e2-small`, `e2-medium`) reserve a flat ~1060m CPU per node for GKE's own system pods regardless of nominal vCPU size, leaving almost nothing for app pods once the Cloud SQL Auth Proxy sidecars were added. Full story in [Decisions](decisions.md#gke-node-sizing-e2-standard-2-not-e2-medium).

**How you'd know it's happening again**: a pod stuck in `Pending` (`kubectl get pods -n sutras`) with a `FailedScheduling` event citing `Insufficient cpu`, and — separately — the [uptime checks](operations.md#health-checks) on `app.sutras.dev`/`api.sutras.dev` failing if it gets bad enough to take the whole app down.

**The next bottleneck in line after compute** is Redis — not because of load, but because of the [durability gap already flagged in Decisions](decisions.md#redis-cache-and-queue-on-one-instance-with-no-persistence-in-production): every node-pool autoscale event that reschedules the Redis pod is a chance to silently lose in-flight pipeline jobs, and that chance goes up, not down, as the pool scales up and down more often under real load.

**After that**, Cloud SQL — `db-f1-micro` is a shared-core, low-connection-limit tier with no read replica and no HA standby; a genuine traffic spike would show up first as connection exhaustion or query latency, with no failover path today if the instance itself has a problem.

## Next steps

The full prioritized list — including everything above, plus the smaller product/security gaps already known and written down in the app repo's own `functionality.md` — lives in [Roadmap](roadmap.md). The headline items directly tied to this page:

1. **Redis persistence** (a PersistentVolumeClaim, or a move to Memorystore once the cost is justified) — closes the biggest current reliability gap for the least effort.
2. **A HorizontalPodAutoscaler on `backend`**, once traffic is real enough to need it — today, node-level autoscaling exists but nothing scales pods within a node.
3. **A read replica or connection pooler (e.g. PgBouncer) in front of Cloud SQL** — not needed yet at current load, but the first thing to reach for once connection exhaustion, not CPU, is the bottleneck.
4. **`replicaCount: 2` + a PodDisruptionBudget** for `backend`/`nginx` — removes the brief per-deploy downtime and the single-node-failure blast radius, once that stops being an acceptable tradeoff at this traffic level.

See [Roadmap](roadmap.md) for the full Now/Next/Later breakdown across infrastructure, security, and product gaps.
