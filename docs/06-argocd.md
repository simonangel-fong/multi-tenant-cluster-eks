# ArgoCD

goal

- ArgoCD manages all in-cluster workloads via GitOps
- app-of-apps: one root `Application`
- install add-ons and votting app

---

## repo layout

```
argocd/
├─ 01-root.yaml          # app-of-apps entry point
└─ apps/
```

---

## delivery phases

| #    | phase                    | description                                                                                                                                   |
| ---- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 7.1  | bootstrap root           | create app-of-apps                                                                                                                            |
| 7.2  | install ESO              | deploy eso via helm;                                                                                                                          |
| 7.3  | test eso                 | add sample `aws secret` via terraform; verify the sample secret in cluster via ESO                                                            |
| 7.4  | albc                     | install albc                                                                                                                                  |
| 7.5  | TG binding               | create ssm parameter to store TG arn; `TargetGroupBinding` reference via ESO                                                                  |
| 7.6  | karpenter                | configure karpenter in TF codes; install karpenter via helm                                                                                   |
| 7.7  | configure node pool      | create node pool; test pod schedules by a sample pod                                                                                          |
| 7.8  | voting-app               | update the app values; deploy in cluster                                                                                                      |
| 7.9  | ~~expose traffic http~~  | **skipped** — TF-managed ALB + `TargetGroupBinding` already exposes HTTP; Gateway API adds no value for a single-service topology             |
| 7.10 | ~~install cert-manager~~ | **deferred** — revisit when Istio lands; Istio's Citadel handles workload mTLS, cert-manager only needed if a public listener requires DNS-01 |
| 7.11 | enable tls               | ACM cert (DNS-validated via Route53) on the ALB/API GW; TF-native, no cert-manager dependency                                                 |
| 7.12 | ~~install e-dns~~        | **deferred** — DNS currently managed in TF (Cloudflare provider); revisit in refactor stage to migrate hostname ownership from TF to cluster (Istio ingress, per-service records) |
| 7.13 | ~~configure e-dns~~      | **deferred** — see 7.12                                                                                                                       |

---

## Development

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo

kubectl -n argocd port-forward svc/argocd-server 8080:443

kubectl apply -f argocd/00-root.yaml

kubectl -n argocd patch app/00-root -p '{"metadata":{"finalizers":[]}}' --type merge
kubectl -n argocd patch app/eso -p '{"metadata":{"finalizers":[]}}' --type merge
kubectl -n argocd patch app/tg-binding -p '{"metadata":{"finalizers":[]}}' --type merge
```

- ESO

```sh
kubectl -n external-secrets get sa
```

- Confirm

```sh
curl -i https://voting.arguswatcher.net/healthz
# HTTP/1.1 200 OK
# Date: Mon, 06 Jul 2026 18:59:40 GMT
# Content-Type: application/json
# Content-Length: 15
# Connection: keep-alive
# server: uvicorn
# apigw-requestid: AGQskhbyYosEMkg=

# {"status":"ok"}

curl -v https://voting.arguswatcher.net/healthz
# * Host voting.arguswatcher.net:443 was resolved.
# * IPv6: (none)
# * IPv4: 16.55.13.83, 15.222.154.84
# *   Trying 16.55.13.83:443...
# * Connected to voting.arguswatcher.net (16.55.13.83) port 443
# * ALPN: curl offers h2,http/1.1
# * TLSv1.3 (OUT), TLS handshake, Client hello (1):
# *  CAfile: /etc/ssl/certs/ca-certificates.crt
# *  CApath: /etc/ssl/certs
# * TLSv1.3 (IN), TLS handshake, Server hello (2):
# * TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
# * TLSv1.3 (IN), TLS handshake, Certificate (11):
# * TLSv1.3 (IN), TLS handshake, CERT verify (15):
# * TLSv1.3 (IN), TLS handshake, Finished (20):
# * TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
# * TLSv1.3 (OUT), TLS handshake, Finished (20):
# * SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256 / X25519 / RSASSA-PSS
# * ALPN: server accepted h2
# * Server certificate:
# *  subject: CN=voting.arguswatcher.net
# *  start date: Jul  6 00:00:00 2026 GMT
# *  expire date: Jan 19 23:59:59 2027 GMT
# *  subjectAltName: host "voting.arguswatcher.net" matched cert's "voting.arguswatcher.net"
# *  issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M01
# *  SSL certificate verify ok.
# *   Certificate level 0: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
# *   Certificate level 1: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
# *   Certificate level 2: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
# * using HTTP/2
# * [HTTP/2] [1] OPENED stream for https://voting.arguswatcher.net/healthz
# * [HTTP/2] [1] [:method: GET]
# * [HTTP/2] [1] [:scheme: https]
# * [HTTP/2] [1] [:authority: voting.arguswatcher.net]
# * [HTTP/2] [1] [:path: /healthz]
# * [HTTP/2] [1] [user-agent: curl/8.5.0]
# * [HTTP/2] [1] [accept: */*]
# > GET /healthz HTTP/2
# > Host: voting.arguswatcher.net
# > User-Agent: curl/8.5.0
# > Accept: */*
# >
# * TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
# < HTTP/2 200
# < date: Mon, 06 Jul 2026 19:00:02 GMT
# < content-type: application/json
# < content-length: 15
# < server: uvicorn
# < apigw-requestid: AGQv6gqG4osEMHw=
# <
# * Connection #0 to host voting.arguswatcher.net left intact
# {"status":"ok"}
```
