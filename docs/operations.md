# Operations

Quick runbook for day-to-day operation of Sutras. This is the thinnest doc on this site, and honestly — that's accurate, not incomplete. Real observability here is one uptime check and one email alert; see [Roadmap](roadmap.md) for what that grows into.

## Health checks

- **External**: GCP Cloud Monitoring runs two synthetic HTTP uptime checks every 5 minutes — `https://app.sutras.dev/` and `https://api.sutras.dev/health` — each with a 10s timeout, checking for a valid, SSL-verified 2xx response.
- **In-cluster**: `nginx` exposes `/health` (liveness) and `/health/ready` (readiness) that Kubernetes probes every 10s; `backend` is probed with a raw TCP check on its php-fpm port; `worker` has no HTTP surface at all, so its liveness probe instead greps `/proc/1/cmdline` inside the container to confirm the `messenger:consume` process is still the one running.
- There is no dashboard beyond Cloud Monitoring's own console — no Grafana, no custom metrics pipeline. What you get is exactly the two uptime checks above, nothing more granular (no per-request latency, no error rate, no queue depth).

## Alerts

One notification channel exists: an email alert, firing if either uptime check (`app.sutras.dev` or `api.sutras.dev/health`) fails for a full 5-minute check cycle (not a single blip — `trigger.count = 1` at a 300s alignment period, so it needs one full failed window, not one failed request). There's no paging, no Slack/Discord integration, and no severity tiering — a full outage and a single flaky check produce the same alert. Acknowledging one today just means going and looking; there's no ack/silence flow.

## Deploying

Day-to-day deploys follow the [release process in Deployment](deployment.md#release-process) — in short: publish a GitHub Release with a `backend-vX.Y.Z` or `frontend-vX.Y.Z` tag, and the matching workflow builds, pushes, migrates, and rolls out automatically. To do the same thing locally (useful for debugging a failed CI run without waiting on GitHub Actions):

```sh
make tf-gcp-init
make release-gcp TAG=<version>       # backend + nginx: build, push, migrate, deploy
make release-frontend                # frontend: build, deploy to Cloudflare Worker
```

Watch the rollout directly if you want to see it land in real time:

```sh
kubectl rollout status deployment backend -n sutras
kubectl rollout status deployment worker -n sutras
```

## Rolling back

There is no automated rollback — `kubectl rollout status` failing in CI just fails the pipeline, it doesn't revert anything. To roll back by hand:

```sh
helm history sutras -n sutras                  # find the last-good revision number
helm rollback sutras <revision> -n sutras
kubectl rollout status deployment backend -n sutras
```

A production smoke suite exists (`e2e/`, `npm run test:production` — a small, deliberately minimal happy-path Playwright suite, not the full local suite) to confirm the app actually works post-rollback, but it's run by hand, not wired into either the release pipeline or this rollback flow yet — see [Roadmap](roadmap.md).

**Database migrations don't automatically roll back** with a Helm rollback — a migration Job runs as a `pre-upgrade` hook on every `helm upgrade`, and reverting the app version doesn't reverse a migration that already ran. A backward-incompatible migration needs its own down-migration or a manual fix, considered before rolling back, not after.

## Common incidents

- **A pod is stuck `Pending` with `FailedScheduling: Insufficient cpu`.** Has happened twice already (see [Scaling](scaling.md#what-breaks-first)), both times because the node pool's schedulable CPU was smaller than it looked on paper. Check `kubectl describe pod <pod> -n sutras` for the exact reason, and `kubectl top nodes` for current allocation. If the node pool is genuinely out of room (not a config regression), the autoscaler should self-heal within a few minutes by adding a node (max 3) — if it doesn't, check `gcloud container node-pools describe sutras-default-pool` for the autoscaling config actually being what `gke.tf` says it should be.
- **A migration Job from a previous release is still sitting around.** Helm's `hook-delete-policy` doesn't reliably self-clean — confirmed live, a completed `migrate-N` Job once sat for 22+ hours needing a manual `kubectl delete job`. `ttlSecondsAfterFinished: 3600` is now set on the Job spec specifically to stop this from recurring; if it's back, that field regressed.
- **A fresh `helm upgrade --install` fails with `serviceaccount sutras-workload not found`.** Root cause of three straight failed releases previously: the Workload Identity ServiceAccount is created as a Helm hook, and plain (non-hook) templates apply *after* hooks run — the migration Job (which needs that ServiceAccount) has an earlier hook-weight now specifically to fix this ordering. If it recurs, check that `serviceaccount.yaml`'s hook-weight is still earlier than `migration-job.yaml`'s.
- **The app looks fine but an entry never seems to finish processing.** Given the [known gap in pipeline-completion delivery](decisions.md#how-pipeline-completion-reaches-the-client-still-unresolved), first rule out "it actually finished, the UI just never told you" — reload the page. If it's still `pending`/`processing` after a reload, check whether the Redis pod restarted recently (`kubectl get pod -n sutras -l app=redis` for its age) — a restart there can silently drop an in-flight pipeline job; see [Decisions](decisions.md#redis-cache-and-queue-on-one-instance-with-no-persistence-in-production).
