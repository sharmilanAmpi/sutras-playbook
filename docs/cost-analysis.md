# Cost Analysis

What it actually costs to run Sutras, broken down by service — and the hard constraint everything else on this page is answering to: **a self-imposed $100/month ceiling.** This isn't a target to stay comfortably under; it's the actual budget for a side project, and it shapes real architecture decisions elsewhere in this site (in-cluster Redis instead of Memorystore, a Cloudflare Tunnel instead of a GCP load balancer, a zonal cluster instead of regional, AWS run on demand instead of always-on) — see [Cost-saving decisions](#cost-saving-decisions) below.

**A note on precision**: three numbers on this page are real — GCP is currently running on a $300/90-day trial credit (not yet a real monthly bill), AWS spend to date is about $2 total for a handful of on-demand testing sessions, and Claude API usage is budgeted at roughly $5/month at current volume. Everything else is a **list-price estimate**, computed from each provider's published pricing for the exact instance types and configuration actually provisioned (read straight out of the Terraform in this repo, not guessed) — not pulled from an invoice. Treat the totals as "what this should cost," to be corrected against real bills once the GCP trial ends.

## Summary

| | Estimated monthly cost | Basis |
|---|---|---|
| **GCP production, currently observed** | **~$118–120** | List-price estimate — the node pool is **actually running 2 nodes right now**, not the 1-node floor it's sized to idle at |
| GCP production, at the autoscaler's 1-node floor | ~$65–70 | List-price estimate — where `min_node_count = 1` says it should mostly sit; not what's happening in practice at the moment |
| GCP production, autoscaled to 3 nodes | ~$165 | List-price estimate — the realistic worst case if load pushes the pool to its max |
| AWS UAT, if left running 24/7 | ~$135 | List-price estimate — this is exactly why it isn't left running (see below) |
| AWS UAT, actual spend to date | **$2** | Real — a few hours of on-demand `terraform apply` / `terraform destroy` cycles |
| Claude API | **~$5** | Real, current usage-based estimate at today's volume |
| Cloudflare (DNS, Tunnel, Workers Static Assets) | $0 | Free tier covers all of this at current traffic |
| Terraform Cloud (remote state) | $0 | Free tier |
| Codecov | $0 | Free tier |
| **Total, current real-world spend** | **~$123–125/month** — over the $100 budget | 2 nodes running (not 1) + Cloud SQL + Claude; AWS only runs occasionally |

**This is currently over budget, and the reason why is an open question, not a resolved one.** The node pool is provisioned to autoscale down to a 1-node floor at low load (see `gke.tf`'s `min_node_count = 1`, quoted in [Decisions](decisions.md#gke-node-sizing-e2-standard-2-not-e2-medium)) — but right now it's sitting at 2 nodes, not 1, and hasn't scaled back down. Whether that's the autoscaler correctly responding to real sustained load, a scale-down cooldown/threshold not yet triggered, or something pinning a second node up unnecessarily hasn't been root-caused yet — worth checking directly against `kubectl get nodes` / GKE's own autoscaler event log before assuming either explanation.

## Compute platform comparison

The question this project keeps coming back to: AWS is provably the expensive option here, and Cloud Run would very likely beat GKE on both cost and effort — so why is GKE the one that's actually always-on? See the [full reasoning in Decisions](decisions.md#cluster-compute-platform-gke-standard-not-autopilot-not-cloud-run); the numbers behind it:

| Platform | Estimated monthly cost (this workload) | Ops overhead | Why / why not |
|---|---|---|---|
| **GKE Standard** (current, production) | ~$118–120 currently observed (2 nodes) — sized to idle at ~$65–70 (1 node), up to ~$165 at max autoscale (3 nodes) | Highest — node pools, Helm, `kubectl`, NetworkPolicy, manual cluster upgrades | Chosen deliberately for the Kubernetes operational experience, not because it's the cheapest fit for this traffic level |
| **Cloud Run** (not used) | ~$10–30 — pay-per-use compute (likely $0–10 at this traffic, on Cloud Run's free tier) + Cloud SQL (~$10) + a managed/hosted Redis substitute (e.g. Upstash, ~$0–10 at this scale) | Lowest — no cluster to manage, scale-to-zero, no node sizing incidents to have | Would very likely be the objectively better fit for this app's actual traffic; not chosen specifically because it wouldn't teach node-pool operations |
| **AWS ECS Fargate** (UAT only, on demand) | ~$135 if run 24/7 (see breakdown below) | Medium — no EC2 patching, but a full VPC/ALB/NAT stack to maintain | Real, but deliberately not run continuously — see [Decisions](decisions.md#dual-cloud-split-aws-for-uat-gcp-for-production-and-aws-only-runs-on-demand) |

The GKE-vs-Cloud-Run gap (~$40–50/month at the low end) is the single largest line item that's a skill-signaling choice rather than an engineering requirement — worth being upfront about rather than presenting GKE as the "correct" answer for a workload this size.

## Compute (GCP — GKE)

- **Node pool**: `e2-standard-2` (2 vCPU / 8GB), autoscaled 1–3 nodes. On-demand list price ≈ $0.067/hour/node (`us-central1`) → **≈ $49/month at 1 node** (the autoscaler's floor), **≈ $98/month at 2 nodes** (what's actually running right now), **≈ $147/month at 3 nodes** (the ceiling).
- **Cluster management fee**: GKE bills $0.10/hour per cluster, but every billing account gets one zonal cluster's management fee waived — this cluster is zonal, so the fee is expected to be **$0**.
- **Boot disks**: 20GB PD-SSD per node ≈ $3.40/month/node → **≈ $3–10/month** depending on node count (currently 2 nodes ≈ $6.80/month).
- No pod-level autoscaling exists (no HPA in the Helm chart) — the numbers above are the entire compute-scaling story today; see [Scaling](scaling.md).

## Database (GCP — Cloud SQL)

`db-f1-micro`, zonal (no HA), Postgres, 10GB SSD, daily backups. List-price estimate: **≈ $8–10/month instance** + **≈ $1.70/month storage** ≈ **~$10–12/month total**. No read replica, no HA standby — see [Scaling](scaling.md) for what that means under load.

## Caching (in-cluster Redis)

Effectively **$0 incremental cost** — it's a pod on a node already being paid for, not a separate line item. That's the entire reason it's self-hosted rather than on Memorystore: GCP's smallest Memorystore Basic-tier instance would cost roughly as much per month as the node pool itself at its 1-node floor. The cost saved here is real; so is the durability given up for it — see [Decisions](decisions.md#redis-cache-and-queue-on-one-instance-with-no-persistence-in-production).

## Networking / CDN (Cloudflare)

DNS, the Cloudflare Tunnel, and Workers Static Assets for the frontend are all on Cloudflare's free tier at this traffic level — **$0/month**. This is also why there's no GCP load balancer or NAT Gateway in production: an external HTTP(S) Load Balancer alone runs close to $20/month before any traffic, and a NAT Gateway is billed hourly plus per-GB regardless of whether it's actually used — both avoided by the Tunnel + Workers approach. See [Decisions](decisions.md#ingress-path-cloudflare-tunnel-workers-not-a-gcp-load-balancer).

## Third-party APIs

The Claude API, called from every stage of the [AI pipeline](architecture.md#the-ai-pipeline), is budgeted at **~$5/month** at current entry volume. The self-hosted `ai-server/` prototype exists specifically as a pre-built escape hatch if this line item ever becomes the constraint instead of infrastructure — see [Decisions](decisions.md#self-hosted-ai-models-prototyped-not-wired-in).

## AWS UAT, if left running 24/7

Real spend on AWS to date is about **$2 total** — a few hours across several `terraform apply` / `terraform destroy` cycles, not a running environment. Here's the list-price estimate for what leaving it running continuously *would* cost, which is the actual reason it isn't:

| Resource | Estimated monthly cost |
|---|---|
| NAT Gateway (hourly + data processing) | ~$36 |
| Application Load Balancer (hourly + LCU) | ~$20–25 |
| ECS Fargate — 3 services (`backend`, `nginx`, `frontend`) | ~$30 |
| RDS `db.t4g.micro` + 20GB gp3 storage | ~$15 |
| ElastiCache `cache.t4g.micro` × 2 nodes | ~$26 |
| **Total, if run 24/7** | **~$130–135/month** |

That single environment alone would exceed the entire $100/month budget — which is exactly why UAT is provisioned on demand rather than left up. The NAT Gateway and ALB together (~$56–60/month) are pure fixed cost regardless of traffic, which is also most of why production deliberately avoids both (see [Networking / CDN](#networking-cdn-cloudflare) above).

## Cost-saving decisions

Every one of these was made specifically to stay inside the $100/month ceiling — full context in [Decisions](decisions.md):

- [In-cluster Redis instead of Memorystore](decisions.md#redis-in-cluster-container-not-memorystore) — saves roughly a node's worth of cost per month, at the price of durability.
- [Cloudflare Tunnel + Workers instead of a GCP load balancer](decisions.md#ingress-path-cloudflare-tunnel-workers-not-a-gcp-load-balancer) — avoids ~$20+/month in fixed LB cost entirely.
- [Zonal, not regional, GKE cluster](decisions.md#cluster-compute-platform-gke-standard-not-autopilot-not-cloud-run) — a regional cluster triples control-plane node footprint for HA this project doesn't need yet.
- [AWS/UAT provisioned on demand, not always-on](decisions.md#dual-cloud-split-aws-for-uat-gcp-for-production-and-aws-only-runs-on-demand) — the single largest saving on this page: avoids ~$130/month for an environment only needed in short bursts.
- [Public-IP GKE nodes, no NAT Gateway](deployment.md#production-infrastructure) — mirrors the AWS NAT Gateway cost avoidance, on the GCP side.
- Container Insights disabled on the ECS cluster — a small, explicit line-item cut, commented directly in `ecs.tf`.
