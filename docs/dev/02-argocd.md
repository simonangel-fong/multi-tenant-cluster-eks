# Multi-tenant Platform Runbook - ArgoCD

[Back](../README.md)

- [Multi-tenant Platform Runbook - ArgoCD](#multi-tenant-platform-runbook---argocd)
  - [Repo Layout](#repo-layout)
  - [Login](#login)
  - [Bootstrap](#bootstrap)
  - [Debug](#debug)

---

## Repo Layout

App-of-apps chain, ordered by sync-wave:

`app-of-apps.yaml` (root) → `argocd/bootstrap/` → `argocd/platform-init/` (wave 0) + `argocd/platform-capabilities/` (wave 1) → `tenants/*.json` (ApplicationSet, wave 100)

```
.
├── app-of-apps.yaml                  # root Application; points at argocd/bootstrap/
├── argocd/
│   ├── bootstrap/                    # first-level app-of-apps (wave-ordered)
│   │   ├── 01-platform-init.yaml     # wave 0 — projects + tenants ApplicationSet
│   │   └── 02-platform-capabilities.yaml   # wave 1 — capability Applications
│   │
│   ├── platform-init/                # AppProjects + tenants ApplicationSet
│   │   ├── init.yaml                 # platform AppProject, base namespaces
│   │   ├── tenants-project.yaml      # AppProject for ApplicationSet-generated apps
│   │   └── tenants-appset.yaml       # generator: reads tenants/*.json → tenant-<name>
│   │
│   └── platform-capabilities/        # cluster-wide capabilities (sync-wave 10–40+)
│       ├── compute/                  # Karpenter + NodePools + EC2NodeClasses
│       ├── storage/                  # EBS CSI + StorageClasses (gp3, gp3-iops)
│       ├── networking/               # Istio ambient, ALBC, external-dns, Gateway API CRDs
│       └── security/                 # cert-manager, ESO, Kyverno + policies
│
├── tenant-chart/                     # Helm chart rendered per tenant by ApplicationSet
│   ├── Chart.yaml
│   ├── values.yaml                   # baseline quota, LimitRange defaults
│   └── templates/                    # Namespace, AppProject, NetworkPolicy, PeerAuth, RQ, LR
│
└── tenants/                          # one JSON per onboarded team (schema: name, sourceRepo, manifestPath)
    ├── team-a.json
    └── team-b.json
```

**How a tenant is born:**

1. A JSON file lands at `tenants/<team>.json`.
2. The `tenants` ApplicationSet in `platform-init/tenants-appset.yaml` matches it and templates a new `Application` `tenant-<name>` with two sources: `tenant-chart/` (guardrails) and the tenant's own `sourceRepo` (workloads).
3. ArgoCD syncs both into the tenant's namespace at wave 100.

### Sync-wave order

Every Application carries an `argocd.argoproj.io/sync-wave` annotation. Lower numbers sync first; ArgoCD blocks on health before advancing.

| Wave    | Application                          | Purpose                                                       |
| :-----: | ------------------------------------ | ------------------------------------------------------------- |
| **0**   | `01-platform-init`                   | AppProjects (`platform`, `tenants`) + tenants ApplicationSet. |
| **1**   | `02-platform-capabilities`           | Fans out to every capability Application below.               |
| 10      | `platform-karpenter`                 | Karpenter controller.                                         |
| 11      | `platform-karpenter-nodes`           | `NodePool` + `EC2NodeClass` for `general` / `database` / `gpu`. |
| 20      | `platform-storage-classes`           | `gp3` (default) and `gp3-iops` StorageClasses.                |
| 30      | `platform-cert-manager`              | cert-manager controller.                                      |
| 30      | `platform-eso`                       | External Secrets Operator controller.                         |
| 30      | `platform-kyverno`                   | Kyverno admission controller.                                 |
| 31      | `platform-eso-resources`             | `ClusterSecretStore` + ESO Namespaces + upstream secrets.     |
| 32      | `platform-cert-manager-resources`    | `ClusterIssuer` (Let's Encrypt DNS-01).                       |
| 33      | `platform-kyverno-policies`          | `ClusterPolicy` set — lands last so tenants aren't rejected before prerequisites exist. |
| 40      | `platform-albc`                      | AWS Load Balancer Controller.                                 |
| 40      | `platform-gateway-api-crds`          | Gateway API v1 CRDs.                                          |
| 41      | `platform-istio-base`                | Istio CRDs + base cluster resources.                          |
| 42      | `platform-istio-cni`                 | Istio CNI plugin.                                             |
| 42      | `platform-istiod`                    | Istio control plane.                                          |
| 43      | `platform-istio-ztunnel`             | Ambient data plane (per-node ztunnel).                        |
| 44      | `platform-istio-gateway`             | Shared `Gateway` + wildcard `Certificate` + `istio-ingress` namespace. |
| 44      | `platform-external-dns`              | Route 53 record writer (reads `HTTPRoute.spec.hostnames`).    |
| **100** | `tenant-<name>` (× N)                | Per-tenant Applications generated by the ApplicationSet.      |

**Reading the ordering:**

- Waves `0–1` establish the app-of-apps graph.
- Waves `10–20` bring compute and storage online (nodes must exist before pods can land).
- Wave `30` starts the three security controllers in parallel; their resources (`31/32/33`) follow strictly serially so CRDs exist before instances.
- Waves `40–44` build the ingress chain bottom-up: ALBC + CRDs → Istio base → CNI + istiod → ztunnel → Gateway + DNS.
- Wave `100` opens the cluster to tenants — every prerequisite is guaranteed green.

---

## Login

Points kubeconfig at the cluster, port-forwards the UI, and logs the CLI in.

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev

# UI: https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443

# initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo

# CLI login (with port-forward running)
argocd login localhost:8080 --username admin --insecure

# inspect
kubectl -n argocd get applications,appprojects
argocd app list
```

---

## Bootstrap

One-time setup for a fresh cluster. Applying `root.yaml` triggers the app-of-apps chain; from that point, ArgoCD self-manages via git.

Before applying, fill in these placeholders in the platform charts:

| Chart     | Field                    | Value                            |
| --------- | ------------------------ | -------------------------------- |
| Karpenter | `clusterName`            | `<eks_cluster_name>`             |
| Karpenter | `interruptionQueue`      | `<karpenter_queue_name>`         |
| Karpenter | `EC2NodeClass.role`      | `<karpenter_node_role_name>`     |
| ALBC      | `clusterName`, `vpcId`   | `<eks_cluster_name>`, `<vpc_id>` |
| Gateway   | `aws-load-balancer-name` | `<eks_cluster_name>`             |

Then apply:

```sh
aws eks update-kubeconfig --region ca-central-1 --name multi-tenant-eks-dev
kubectl apply -f app-of-apps.yaml
```

Verify:

```sh
argocd app list
# every app should reach Synced + Healthy; platform apps first, then tenants
```

---

## Debug

```sh
# inspect
kubectl -n argocd get app <name> -o yaml
argocd app get <name>
argocd app history <name>

# force sync
argocd app sync <name>
argocd app sync <name> --prune
argocd app sync <name> --force --replace     # last resort: server-side replace

# clear a stuck operation ("operation in progress" forever)
kubectl -n argocd patch app/<name> --type merge \
  -p '{"status":{"operationState":null},"operation":null}'
argocd app terminate-op <name>

# refresh cache (git out of sync with UI)
argocd app get <name> --refresh
argocd app get <name> --hard-refresh

# remove finalizer so a stuck app can be deleted
kubectl -n argocd patch app/<name> --type merge \
  -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd delete app <name>

# remove all
kubectl delete applications.argoproj.io --all -n argocd --cascade
kubectl get application -n argocd -o name | xargs -I {} kubectl patch {} -n argocd --type merge -p '{"metadata":{"finalizers":null}}'

# bulk: clear finalizers + delete all apps
kubectl -n argocd get apps -o name \
  | xargs -I {} kubectl -n argocd patch {} --type merge \
      -p '{"metadata":{"finalizers":[]}}'
kubectl -n argocd delete apps --all

# nuclear: delete app without cascading to cluster resources
argocd app delete <name> --cascade=false

# controller logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-application-controller --tail=200 -f
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-repo-server           --tail=200 -f
```
