# Sutras Playbook

Sutras is a personal-scale SaaS app for micro-learning and knowledge capture, built solo: a place to record, in a sentence or two, what you actually learned today, with an AI pipeline that tightens the wording and a tag-based structure that turns scattered entries into something you can look back on.

*Value and visibility for what you learned today — learning that sticks, growth that shows.*

| | |
|---|---|
| Landing | [sutras.dev](https://sutras.dev) |
| App | [app.sutras.dev](https://app.sutras.dev) |

This site itself isn't that app — it's a case study of how it's built, deployed, and operated — real architecture, real infrastructure decisions, real tradeoffs, and the parts that are still genuinely unfinished. No application source code lives here, just the engineering thinking behind the system.

## The constraint everything else answers to

**A self-imposed $100/month budget.** That number shows up as a real design decision on nearly every page here: why Redis runs in-cluster instead of on a managed service, why there's a Cloudflare Tunnel instead of a cloud load balancer, why one environment (AWS/UAT) only exists on demand instead of always-on, why the GKE node pool is sized the way it is. See [Cost Analysis](cost-analysis.md) for the full breakdown, and [Decisions](decisions.md) for the reasoning behind each individual call.

Three other things worth knowing before reading further:

- **This is a small system, held to real standards anyway.** It doesn't need enterprise scale, but it isn't allowed to be sloppy or insecure either — encryption at rest, least-privilege networking, no static credentials, secrets out of source control, all present even where the traffic doesn't demand it yet.
- **Some parts are over-built for the current traffic, on purpose** (a full AI audit trail, a curator review workflow, a second cloud environment) — because part of the point of this project is demonstrating engineering judgment, not just shipping the minimum. Other parts are deliberately left thin (observability, HA, backups in some places) because the cost or effort isn't justified yet. Both kinds of choice are called out explicitly rather than left to guess at — see [Decisions](decisions.md) and [Roadmap](roadmap.md).
- **Nothing here is finished, and that's stated plainly rather than hidden.** Every open question, known gap, and rough edge found while writing this site is tracked in [Roadmap](roadmap.md) instead of glossed over.

## Contents

- **[Architecture](architecture.md)** — how the app is structured, backend/frontend layers, the AI processing pipeline.
- **[Deployment](deployment.md)** — environments, cloud providers, release process.
- **[Operations](operations.md)** — runbook: deploys, rollbacks, health checks, alerts.
- **[Cost Analysis](cost-analysis.md)** — what it actually costs to run, broken down by service, and how it compares to the alternatives that weren't chosen.
- **[Scaling](scaling.md)** — current limits and what changes as load grows.
- **[Decisions](decisions.md)** — an ADR-style log of the "why" behind key infra choices, including the ones that traded cost/simplicity for a chance to learn something.
- **[Roadmap](roadmap.md)** — every open gap on this site, prioritized: what's worth fixing now, what's waiting on real traffic, and what's a deliberate "not yet."

Every page links forward and backward into the others on purpose — a decision on one page points at the constraint that drove it and the doc where it shows up in practice, so the full picture holds together as one system rather than six separate write-ups.
