# Multi-tenant Platform Guide - Onboarding

[Back](../../README.md)

- [Multi-tenant Platform Guide - Onboarding](#multi-tenant-platform-guide---onboarding)
  - [Overview](#overview)
  - [What the Tenant Provides](#what-the-tenant-provides)
  - [Manifest Requirements](#manifest-requirements)
  - [First Deploy](#first-deploy)
  - [Related Guides](#related-guides)
  - [Demos](#demos)

---

## Overview

Onboarding is a two-party flow:

1. The **tenant** hands over three inputs (below) and a Git repo containing valid manifests.
2. The **platform engineer** commits one JSON file at `tenants/<team>.json` in the platform repo. GitOps handles the rest — namespace, `AppProject`, `ApplicationSet`, subdomain, TLS, and policy.

Time to live URL after the platform PR merges: ~3 minutes for a stateless app, ~2 additional minutes for a stateful app.

---

## What the Tenant Provides

Three fields, handed to the platform engineer:

| Field          | Example                                                       | Purpose                             |
| -------------- | ------------------------------------------------------------- | ----------------------------------- |
| `name`         | `team-a`                                                      | Namespace, subdomain, `team` label. |
| `sourceRepo`   | `https://github.com/simonangel-fong/eks-multi-tenant-cluster` | Repo containing the manifests.      |
| `manifestPath` | `demo-app/team-a`                                             | Path inside `sourceRepo`. Plain-manifest directory or Helm chart — auto-detected. |

The platform engineer commits these into `tenants/<team>.json` — see [platform/onboarding.md](../platform/onboarding.md) for the platform side.

---

## Manifest Requirements

Every workload manifest must satisfy the cluster's admission policies. Non-compliant manifests are **rejected at admission** — pods will not schedule.

**Required on every workload:**

- `metadata.labels.team: <team>` — required by Kyverno.
- `resources.requests` — both `cpu` and `memory`.
- `readinessProbe` and `livenessProbe` on every container.
- `metadata.annotations.runbook` — a URL to the tenant's runbook.
- Image tag is **not** `:latest` and comes from the approved registry list.

**Compute** — pick a workload class via `nodeSelector`. See [compute.md](compute.md).

**Storage** — `PVC` with `storageClassName: gp3` (default) or `gp3-iops` (high-IOPS, `Retain` reclaim).

**Ingress** — one `HTTPRoute` attached to `istio-ingress/istio-ingress`, hostname under `<team>.arguswatcher.net`. See [network.md](network.md).

The full Kyverno policy set is documented in [platform/security.md](../platform/security.md#kyverno-policy-set).

---

## First Deploy

Once the platform PR is merged and the tenant's own manifest PR lands:

```sh
# Workload is scheduled and healthy
kubectl -n <team> get pods,svc,httproute

# Public URL is live
curl -I https://<team>.arguswatcher.net    # expect 200/301, valid TLS cert
```

If pods are `Pending` or `HTTPRoute` shows `Accepted: False`, see the debugging bullets in [compute.md](compute.md#rules-of-the-road) and [network.md](network.md#rules-of-the-road).

---

## Related Guides

- [compute.md](compute.md) — requesting nodes by workload class.
- [network.md](network.md) — exposing services via `HTTPRoute`.
- [platform/onboarding.md](../platform/onboarding.md) — what happens on the platform side after the JSON lands.

---

## Demos

Two reference tenants ship in this repo, exercising every capability the platform provides:

| Tenant | Profile                                              | Capabilities                                             | URL                             |
| ------ | ---------------------------------------------------- | -------------------------------------------------------- | ------------------------------- |
| Team A | Stateless nginx serving a `ConfigMap`-mounted page.  | Compute (`general`), ingress + TLS + DNS.                | `team-a.arguswatcher.net`       |
| Team B | Full-stack to-do app: web + Postgres (PVC).          | Compute (`general` + `database`), storage (`gp3-iops`, `Retain`), ingress + TLS + DNS. | `team-b.arguswatcher.net`       |

Manifests: [demo-app/team-a](../../demo-app/team-a), [demo-app/team-b](../../demo-app/team-b).

![team-a web](../img/team-a.png)

![team-b web](../img/team-b.png)
