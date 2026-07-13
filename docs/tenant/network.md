# Multi-tenant Platform Guide - Network

[Back](../../README.md)

- [Multi-tenant Platform Guide - Network](#multi-tenant-platform-guide---network)
  - [Overview](#overview)
  - [What Tenants Get for Free](#what-tenants-get-for-free)
  - [How to Expose a Service](#how-to-expose-a-service)
  - [Example](#example)
  - [Rules of the Road](#rules-of-the-road)

---

## Overview

The platform ships out-of-the-box ingress, TLS, DNS, and east-west mTLS. A tenant ships one `HTTPRoute` and gets a routable, TLS-terminated hostname — no AWS, DNS, or certificate wiring required.

---

## What Tenants Get for Free

| Capability     | Provided by the platform                                                  |
| -------------- | ------------------------------------------------------------------------- |
| Public URL     | Any hostname under `<team>.arguswatcher.net`                              |
| TLS            | Wildcard `*.arguswatcher.net` — valid cert, auto-renewed                  |
| Load balancer  | Shared internet-facing NLB fronting the cluster                           |
| DNS record     | Created automatically from `HTTPRoute.spec.hostnames`                     |
| East-west mTLS | Automatic between pods in ambient-enabled namespaces (no code changes)    |

---

## How to Expose a Service

Ship one `HTTPRoute` in the tenant namespace, attached to the shared Gateway on the `https` (443) listener.

| Field                          | Value                                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| `parentRefs[0].name`           | `istio-ingress`                                                    |
| `parentRefs[0].namespace`      | `istio-ingress`                                                    |
| `parentRefs[0].sectionName`    | `https` (bind to the TLS listener explicitly)                      |
| `hostnames`                    | Any subdomain of `<team>.arguswatcher.net`                         |
| `rules[].backendRefs`          | The tenant's `Service` and port                                    |

No Service annotations, no ingress annotations, no certificate references.

---

## Example

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web
  namespace: team-a
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-ingress
      sectionName: https              # bind to the 443 TLS listener
  hostnames:
    - team-a.arguswatcher.net
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80                    # backend Service port, not Gateway listener
```

DNS, TLS, and load balancing are wired automatically. Verify with:

```sh
curl -I https://team-a.arguswatcher.net    # expect 200/301 and a valid cert
```

For multi-rule, header-based, or method-based matching, see the [Gateway API HTTPRoute docs](https://gateway-api.sigs.k8s.io/api-types/httproute/).

---

## Rules of the Road

- **Hostnames stay within `<team>.arguswatcher.net`.** Kyverno rejects any `HTTPRoute` that claims a hostname outside the tenant's subdomain.
- **Always bind to the `https` listener** (`sectionName: https`). The `http` listener (port 80) exists for ACME HTTP-01 fallback only and does not perform TLS.
- **Ambient mTLS is automatic** — namespaces are labeled `istio.io/dataplane-mode=ambient` at onboarding. No sidecar injection, no pod restarts.
- **Don't remove the default `NetworkPolicy`.** The namespace ships with `default-deny` **plus** `allow-platform-ingress-and-dns` — the second policy is required for the shared Gateway, ambient mesh, DNS, and kubelet probes to work. Layer additional allow-rules on top; do not replace it.
- **Health probes need the SNAT allow-rule.** Ambient rewrites kubelet probes to `169.254.7.127/32`. Any tenant-authored NetworkPolicy must keep the ingress rule from `169.254.7.127/32`, or every probe times out.
- **Custom (non-`arguswatcher.net`) domain?** File a platform request — adds a Gateway listener + certificate. Not part of the default contract.
- **Route not resolving?** Check `kubectl describe httproute` for `Accepted: False` — usually a hostname outside the subdomain or a `backendRefs` Service with no endpoints.
