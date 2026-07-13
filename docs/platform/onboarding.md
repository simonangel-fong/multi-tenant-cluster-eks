# Multi-tenant Platform Runbook - Tenant Onboarding

[Back](../../README.md)

- [Multi-tenant Platform Runbook - Tenant Onboarding](#multi-tenant-platform-runbook---tenant-onboarding)
  - [Overview](#overview)
  - [Intake](#intake)
  - [Onboarding Steps](#onboarding-steps)
  - [What the Blueprint Renders](#what-the-blueprint-renders)
  - [Verification](#verification)
  - [Offboarding](#offboarding)
  - [Common Issues](#common-issues)

---

## Overview

Onboarding is a **single-file PR**. Committing one JSON at `tenants/<team>.json` triggers the `tenants` ApplicationSet ([tenants-appset.yaml](../../argocd/platform-init/tenants-appset.yaml)), which renders one Argo CD `Application` per tenant (`tenant-<team>`, sync-wave `100`) with **two sources**:

- **Source 1** — [tenant-chart/](../../tenant-chart/) — platform-owned guardrails (namespace, PeerAuthentication, NetworkPolicy, ResourceQuota, LimitRange, tenant AppProject).
- **Source 2** — the tenant's `manifestPath` — the workload itself.

One Application, no nested apps, no finalizer races. Reference: [tenants/team-a.json](../../tenants/team-a.json).

---

## Intake

**Schema fields** (required in `tenants/<team>.json`):

| Field          | Example                                                       | Used for                           |
| -------------- | ------------------------------------------------------------- | ---------------------------------- |
| `name`         | `team-a`                                                      | namespace, subdomain, `team` label |
| `sourceRepo`   | `https://github.com/simonangel-fong/eks-multi-tenant-cluster` | `AppProject.sourceRepos`           |
| `manifestPath` | `demo-app/team-a`                                             | `Application.spec.sources[1].path` |

**Out-of-band asks** (handled outside the JSON, before the PR merges):

- AWS access → Pod Identity role + ASM secret paths → Terraform PR against [infra/](../../infra/).
- Quota / tier / IAM overrides → not in the schema today; the chart uses fixed baselines. Extend [tenant-chart/values.yaml](../../tenant-chart/values.yaml) if a tenant needs different limits.

---

## Onboarding Steps

1. **Open a PR** adding `tenants/<team>.json`:

   ```json
   {
     "name": "team-a",
     "sourceRepo": "https://github.com/simonangel-fong/eks-multi-tenant-cluster",
     "manifestPath": "demo-app/team-a"
   }
   ```

   `manifestPath` can be a plain-manifest directory or a Helm chart directory — Argo CD auto-detects.

2. **Provision AWS prerequisites** (if requested) via a separate Terraform PR: Pod Identity role, ASM paths, S3 buckets.
3. **Update `CODEOWNERS`** so the tenant's manifest path requires their team's review.
4. **Merge to `master`.** The ApplicationSet reconciles within ~60s and generates `tenant-<team>`.
5. **Verify** — see [Verification](#verification).

The tenant then opens their own PR against their manifest path. See [../tenant/onboarding.md](../tenant/onboarding.md) for the tenant-facing flow.

---

## What the Blueprint Renders

Templates live in [tenant-chart/templates/](../../tenant-chart/templates/). All target `destination.namespace: <team>`; resources with an explicit `metadata.namespace` (the `AppProject`, which lives in `argocd`) override.

| Resource            | File                                                                                                 | Guarantees                                                                        |
| ------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `Namespace`         | [namespace.yaml](../../tenant-chart/templates/namespace.yaml)                                        | `team=<name>` label; `istio.io/dataplane-mode=ambient` — ztunnel takes over, no sidecars. |
| `PeerAuthentication`| [peer-authentication.yaml](../../tenant-chart/templates/peer-authentication.yaml)                    | `mtls.mode: STRICT` — plaintext peers refused inside the mesh.                    |
| `NetworkPolicy` (deny) | [network-policy-deny.yaml](../../tenant-chart/templates/network-policy-deny.yaml)                 | Default-deny for ingress and egress.                                              |
| `NetworkPolicy` (allow) | [network-policy-allow.yaml](../../tenant-chart/templates/network-policy-allow.yaml)              | Restores platform paths — see [NetworkPolicy rules](#networkpolicy-rules) below.  |
| `ResourceQuota`     | [resource-quota.yaml](../../tenant-chart/templates/resource-quota.yaml)                              | `4/8Gi` requests, `8/16Gi` limits, 10 PVCs.                                       |
| `LimitRange`        | [limit-range.yaml](../../tenant-chart/templates/limit-range.yaml)                                    | Container defaults `100m/128Mi` req, `500m/512Mi` limit.                          |
| `AppProject`        | [app-project.yaml](../../tenant-chart/templates/app-project.yaml)                                    | Name `<team>`, whitelists platform + tenant repos, destination locked to `<team>`, cluster-scoped resources denied. |

Baseline values come from [tenant-chart/values.yaml](../../tenant-chart/values.yaml).

### NetworkPolicy rules

`allow-platform-ingress-and-dns` restores the paths the platform needs on top of default-deny. **Every rule matters** — omitting one breaks day-one traffic:

| Rule                              | Why                                                                                     |
| --------------------------------- | --------------------------------------------------------------------------------------- |
| Ingress from `istio-ingress` ns   | Shared Gateway → tenant pods                                                            |
| Ingress from `istio-system` ns    | ztunnel / waypoint HBONE                                                                |
| Ingress from `169.254.7.127/32`   | **Ambient SNATs kubelet probes to this link-local** — without this, all probes time out |
| Ingress from `10.0.0.0/16`        | Non-ambient probe path (fallback if a pod exits ambient)                                |
| Ingress on TCP 15008 from any ns  | HBONE — east-west ambient mTLS tunnel                                                   |
| Egress UDP/TCP 53 → `kube-system` | DNS                                                                                     |
| Egress to `istio-system`          | ztunnel xDS + upstream to waypoints                                                     |
| Egress to any pod in the namespace| Internal traffic                                                                        |

---

## Verification

```sh
# 1. Application exists and is healthy
argocd app get tenant-<team>
kubectl -n argocd get appproject <team>

# 2. Namespace guardrails applied
kubectl get ns <team> --show-labels                    # team=<team>, istio.io/dataplane-mode=ambient
kubectl -n <team> get peerauthentication,networkpolicy,resourcequota,limitrange

# 3. Ambient mesh has picked up the namespace
istioctl ztunnel-config workloads | grep <team>

# 4. Tenant workload smoke test
kubectl -n <team> get pods,svc,httproute
curl -I https://<team>.arguswatcher.net                # expect 200/301, valid TLS cert
```

---

## Offboarding

```sh
git rm tenants/<team>.json
git commit -m "offboard <team>"
git push
```

The ApplicationSet detects the removal, deletes `tenant-<team>`, and cascades through the namespace and workloads. No manual finalizer patching. Completes within ~60s.

---

## Common Issues

| Symptom                                                               | Likely cause                                                                 | Fix                                                                                                |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Tenant `Application` stuck `Unknown`                                  | `AppProject` `sourceRepos` or `destinations` don't match the Application     | Align repo URL and namespace between `AppProject` and `Application`.                               |
| Kyverno rejects tenant workloads (`require-team-label`, etc.)         | Manifests missing `team` label, requests, probes, or use `:latest`           | Point the tenant at the Kyverno policy list ([security.md](security.md#kyverno-policy-set)).       |
| All pods time out on probes right after onboarding                    | NetworkPolicy missing the `169.254.7.127/32` ambient-SNAT rule               | Re-apply `allow-platform-ingress-and-dns` from the chart.                                          |
| East-west traffic silently dropped between two ambient namespaces     | HBONE (TCP 15008) not allowed in tenant NetworkPolicy                        | Add the `port: 15008` ingress rule.                                                                |
| Tenant hits quota on first deploy                                     | Baseline quota too tight for the workload                                    | Extend `tenant-chart/values.yaml` schema to allow per-tenant overrides.                            |
| `HTTPRoute` rejected by Kyverno (`httproute-hostname-scoped-to-team`) | Hostname not under `<team>.arguswatcher.net`                                 | Tenant must use their subdomain, or platform adds a custom listener + cert.                        |
| Offboard leaves stuck Application                                     | Manual `argocd app delete` bypassed the ApplicationSet                       | Always offboard via `git rm tenants/<team>.json`, not `argocd app delete`.                         |
