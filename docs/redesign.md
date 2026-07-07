# Redesign: Istio + Gateway API + external-dns (Cloudflare)

Removes API Gateway, the Terraform-managed private ALB, and the manual `TargetGroupBinding`. Replaces them with an Istio ambient mesh fronted by a public NLB, DNS managed via external-dns → Cloudflare, and TLS certs issued by cert-manager via Let's Encrypt DNS-01.

## Goals

- No hardcoded AWS ARNs in Kubernetes manifests.
- Clean team-ownership split: Infra / Platform / App.
- App teams self-serve routing via `HTTPRoute` — no Terraform PRs to expose a new service.
- Portable manifests (same YAML works in any cluster/account).
- Fits the roadmap noted in `README.md` (`istio ambient`, `gateway`).

## Non-goals

- Multi-cluster mesh (single cluster for now).
- mTLS to non-mesh workloads (all traffic terminates inside the mesh).
- Waypoint proxy for L7 policy (add later when needed — ambient mode allows this incrementally).

## Target architecture

```
Client (HTTPS)
   ↓
Cloudflare DNS (api.example.com)          ← records written by external-dns
   ↓
Public NLB                                ← created by AWS LBC from Istio's Service
   ↓  (TLS passthrough on :443)
Istio ingress-gateway pod                 ← spun up by istiod from the Gateway CR
   ↓  (TLS termination, HTTPRoute matching)
Ambient mesh (ztunnel)                    ← pod-to-pod mTLS
   ↓
voting-app-api pod :8000
```

## Component ownership

| Layer             | Team     | Owns                                                                                                                      |
| ----------------- | -------- | ------------------------------------------------------------------------------------------------------------------------- |
| Infra (Terraform) | Infra    | VPC, EKS, IAM/IRSA for LBC/ESO/external-dns/cert-manager, Cloudflare API token in AWS Secrets Manager                     |
| Platform (Argo)   | Platform | Istio (base, istiod, CNI, ztunnel), LBC, ESO, external-dns, cert-manager, shared `Gateway`, `ClusterIssuer`, GatewayClass |
| App (Argo)        | App      | Helm chart: Deployment, Service, HTTPRoute — no annotations, no ARNs                                                      |

## What gets deleted

- `infra/aws/30-aws-apigtw-link.tf`
- `infra/aws/31-aws-apigtw-api.tf`
- `infra/aws/20-aws-alb.tf` (entire file — Istio's Service will create the NLB)
- `argocd/apps/tg-binding.yaml`
- `argocd/apps/tg-binding/` directory
- `placeholder_tg_arn` output in `infra/aws/04-outputs.tf`
- `aws_security_group.vpc_link`

## What gets added

### Infra

**`infra/aws/41-cloudflare-secret.tf`** — Cloudflare API token stored in AWS Secrets Manager. ESO pulls it into the cluster.

```hcl
resource "aws_secretsmanager_secret" "cloudflare" {
  name = "${local.common_name}/cloudflare-api-token"
}

resource "aws_secretsmanager_secret_version" "cloudflare" {
  secret_id     = aws_secretsmanager_secret.cloudflare.id
  secret_string = jsonencode({ apiToken = var.cloudflare_api_token })
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}
```

Extend the ESO IAM policy in `infra/aws/13-eks-eso.tf` to grant read on this secret.

**Cloudflare token scope:** `Zone.DNS:Edit` on the target zone — one token serves both external-dns (record writes) and cert-manager (DNS-01 challenges).

### Platform — Istio ambient

Four Argo Applications under `argocd/apps/`:

- **`istio-base.yaml`** — `base` chart (`1.24.0`), namespace `istio-system`, installs CRDs.
- **`istio-cni.yaml`** — `cni` chart, ambient prerequisite.
- **`ztunnel.yaml`** — `ztunnel` chart, per-node mTLS proxy.
- **`istiod.yaml`** — `istiod` chart with `profile: ambient`.

Chart repo: `https://istio-release.storage.googleapis.com/charts`.

### Platform — supporting controllers

**`argocd/apps/external-dns.yaml`** — external-dns with Cloudflare provider, watching Gateway API sources.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    chart: external-dns
    targetRevision: 1.15.0
    helm:
      releaseName: external-dns
      values: |
        provider: cloudflare
        sources:
          - gateway-httproute
          - service
        policy: sync
        txtOwnerId: voting-dev
        env:
          - name: CF_API_TOKEN
            valueFrom:
              secretKeyRef:
                name: cloudflare-api-token
                key: apiToken
  destination:
    server: https://kubernetes.default.svc
    namespace: external-dns
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

**`argocd/apps/cert-manager.yaml`** — cert-manager chart (`v1.16.0`, `installCRDs: true`) in the `cert-manager` namespace.

### Platform — secrets, issuer, gateway

**`argocd/apps/external-dns-secret/external-secret.yaml`** — ESO syncs the Cloudflare token into two namespaces (external-dns, cert-manager).

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secretsmanager
  target:
    name: cloudflare-api-token
  data:
    - secretKey: apiToken
      remoteRef:
        key: voting-dev/cloudflare-api-token
        property: apiToken
```

Duplicate for `namespace: cert-manager`.

**`argocd/apps/cert-manager-issuer/clusterissuer.yaml`** — Let's Encrypt production issuer using Cloudflare DNS-01.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@example.com
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: apiToken
```

**`argocd/apps/istio-gateway/gateway.yaml`** — the shared Gateway. Istio spawns an ingress-gateway Deployment + Service; LBC sees the Service annotations and creates a public NLB.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared
  namespace: istio-ingress
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-tls
            kind: Secret
      allowedRoutes:
        namespaces:
          from: All
```

**`argocd/apps/istio-gateway/certificate.yaml`** — cert-manager Certificate. Produces the `wildcard-tls` Secret consumed above.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-tls
  namespace: istio-ingress
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
```

### App — HTTPRoute in Helm chart

Update `helm/voting-app/templates/06-httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: { { include "voting-app.api.fullname" . } }
  annotations:
    external-dns.alpha.kubernetes.io/target: { { .Values.gateway.nlbHostname } }
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"
spec:
  parentRefs:
    - name: shared
      namespace: istio-ingress
  hostnames:
    - { { .Values.gateway.host | quote } }
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: { { include "voting-app.api.fullname" . } }
          port: { { .Values.service.port } }
```

Update `helm/voting-app/values.yaml`:

```yaml
gateway:
  enabled: true
  host: api.example.com
  nlbHostname: "" # populated per-env in values-dev.yaml / values-prod.yaml
```

Ambient label on the `voting` namespace template:

```yaml
metadata:
  labels:
    istio.io/dataplane-mode: ambient
```

## Design decisions

### TLS termination — at Istio, not at NLB

NLB runs as L4 passthrough on `:443`. Istio terminates TLS using a cert-manager–issued Secret. Rationale: keeps zero AWS ARNs in Git. If TLS were terminated at the NLB, the annotation `service.beta.kubernetes.io/aws-load-balancer-ssl-cert` would need an ACM ARN — the same coupling the redesign aims to avoid.

### Cloudflare orange-cloud (proxy) — off for cutover

Grey-cloud (DNS-only) during migration. Traffic goes direct to the NLB. Enable proxy later once end-to-end works; will require Cloudflare Origin Certificates or a strict-SSL config to keep the CF→NLB leg encrypted properly.

### Cert-manager over ACM

ACM cannot export private keys, so an ACM cert cannot be consumed by Istio for termination. cert-manager + Let's Encrypt with the Cloudflare DNS-01 solver reuses the same API token external-dns already needs. One secret, two consumers, zero AWS identifiers in K8s manifests.

## Migration order

Steps 1–5 are additive — the old API Gateway path keeps serving until step 6.

1. Bump `argocd/apps/albc.yaml` to a chart version shipping AWS LBC ≥ v2.14.
2. Deploy Istio Argo Applications (base → CNI → ztunnel → istiod).
3. Deploy cert-manager + external-dns Argo Applications.
4. Add Cloudflare token: apply Terraform changes; ESO syncs the Secret into `external-dns` and `cert-manager` namespaces.
5. Apply `ClusterIssuer`, then the shared `Gateway` + `Certificate`. Verify:
   - Istio creates an ingress-gateway Service.
   - LBC provisions the NLB.
   - cert-manager issues the wildcard cert.
   - external-dns writes a placeholder record for the gateway Service.
6. Set `gateway.enabled: true` in voting-app values. Add ambient label to the `voting` namespace. Verify `curl https://api.example.com` hits voting-app.
7. Delete the API Gateway Terraform, private ALB, and tg-binding Argo Application. `terraform apply`.
8. (Optional) enable Cloudflare orange-cloud proxy once end-to-end is stable.

## What survives from the current stack

- ArgoCD app-of-apps structure.
- ESO (gains one ExternalSecret for the Cloudflare token).
- Karpenter.
- Helm chart layout — only the HTTPRoute template, namespace label, and values change.
- AWS Load Balancer Controller — no longer manages a specific ALB; provisions NLBs via Service annotations on the Istio gateway.

## What changes conceptually

- No `TargetGroupBinding` anywhere.
- No hardcoded AWS ARNs in Kubernetes manifests.
- App team never touches infra to expose a service — they ship an `HTTPRoute` and DNS/TLS/LB/mesh all flow automatically.
- The AWS LB (NLB) is now a boundary object managed _from inside_ the cluster, not from Terraform. Trade-off: LB lifecycle tied to the K8s Service; if the platform Argo app is deleted, the NLB drops. Acceptable because the Gateway lives at the platform layer, not the app layer.

## Open questions to resolve before implementing

- Which Cloudflare zone will be used, and is the API token already provisioned?
- Which email address for Let's Encrypt registration?
- Wildcard hostname (`*.example.com`) or per-service hostnames?
- Do any current API Gateway features (throttling, JWT authorizers, WAF) need a replacement before cutover? If yes, plan where (Cloudflare WAF, Istio AuthorizationPolicy, or app-level).
