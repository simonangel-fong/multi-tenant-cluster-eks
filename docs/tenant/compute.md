# Multi-tenant Platform Guide - Compute

[Back](../../README.md)

- [Multi-tenant Platform Guide - Compute](#multi-tenant-platform-guide---compute)
  - [Overview](#overview)
  - [Workload Class](#workload-class)
  - [How to Request Compute](#how-to-request-compute)
  - [Examples](#examples)
  - [Rules of the Road](#rules-of-the-road)

---

## Overview

The platform ships out-of-the-box compute capability. Tenants pick a **workload class** by setting a `nodeSelector`, and — for tainted classes — a matching `toleration`. Nodes appear when a pod is scheduled and disappear when the pod is gone.

---

## Workload Class

| Class      | Common usage                                             | Capacity mix     | Toleration required? |
| ---------- | -------------------------------------------------------- | ---------------- | :------------------: |
| `general`  | Stateless (web apps, APIs, workers). **Default choice.** | on-demand + spot |          No          |
| `database` | Stateful with a PVC (databases, queues, caches).         | on-demand only   |         Yes          |
| `gpu`      | GPU-backed (inference, training).                        | on-demand only   |         Yes          |

---

## How to Request Compute

Add a `nodeSelector` to the pod spec. If the class has a taint, add the matching `toleration`. No instance sizes, no `nodeAffinity`, no capacity-type flags.

**`general` — nodeSelector only:**

```yaml
spec:
  nodeSelector:
    workload-class: general
```

**`database` / `gpu` — nodeSelector + toleration:**

```yaml
spec:
  nodeSelector:
    workload-class: <database|gpu>
  tolerations:
    - key: workload-class
      value: <database|gpu>
      effect: NoSchedule
```

---

## Examples

**Stateless web app — `general`:**

```yaml
spec:
  nodeSelector:
    workload-class: general
  containers:
    - name: web
      image: nginx:1.27
      resources:
        requests: { cpu: 100m, memory: 128Mi }
      readinessProbe: { httpGet: { path: /, port: 80 } }
      livenessProbe:  { httpGet: { path: /, port: 80 } }
```

**Postgres — `database`:**

```yaml
spec:
  nodeSelector:
    workload-class: database
  tolerations:
    - { key: workload-class, value: database, effect: NoSchedule }
  containers:
    - name: postgres
      image: postgres:16
      resources:
        requests: { cpu: 250m, memory: 512Mi }
```

**GPU inference — `gpu`:**

```yaml
spec:
  nodeSelector:
    workload-class: gpu
  tolerations:
    - { key: workload-class, value: gpu, effect: NoSchedule }
  containers:
    - name: infer
      image: my-model:1.0
      resources:
        limits:
          nvidia.com/gpu: 1        # required — every gpu pod must request a GPU
```

---

## Rules of the Road

- **Always declare `resources.requests`** — Kyverno rejects pods without CPU + memory requests. See the full policy set in [platform/security.md](../platform/security.md#kyverno-policy-set).
- **Always declare probes** — `readinessProbe` and `livenessProbe` are required.
- **Never pin instance types or AZs** — the platform selects hardware; pinning breaks autoscaling and fails admission.
- **Nodes recycle every 30 days** for AMI patching. Pods can restart at any time — use a `PodDisruptionBudget` to keep a minimum available replica count.
- **Stateful workloads → `database`** — `general` mixes on-demand + spot for cost, so spot pods can be reclaimed. Anything with a PVC or that cannot survive interruption belongs on `database` (on-demand only).
- **HPA is tenant-owned** — the platform ships `metrics-server`; tenants write their own `HorizontalPodAutoscaler`.
- **Don't remove the default `NetworkPolicy`** — the platform's `allow-platform-ingress-and-dns` policy (including the `169.254.7.127/32` rule) is required for kubelet probes to reach ambient-enrolled pods. Layer additional allow-rules on top; do not replace it.
- **Pending pod?** Verify the `nodeSelector` matches a valid class and, for tainted classes, that the toleration is present. If still pending, contact the platform team.
