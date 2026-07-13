# GitHub Page — Build Plan

## Stack
- HTML, CSS, vanilla JS (no framework)
- Deploy: GitHub Pages (already enabled)
- Style reference: [gitops.arguswatcher.net](https://gitops.arguswatcher.net/)

## File layout
```
docs/
  index.html            # landing (replaces index.md)
  assets/
    css/site.css
    js/site.js
  img/                  # existing screenshots + architecture.png
```
Sub-pages under `tenant/`, `platform/`, `dev/` stay as Markdown (Jekyll renders them).

---

## Phases

### 00 — Bootstrap
- Delete `docs/index.md`
- Create `docs/index.html` with `layout: none` front matter and a "hello world" body
- Verify GitHub Pages serves the raw HTML

### 01 — Skeleton
- Sticky top nav with anchor links: Idea · Architecture · Platform · Tenant · Docs
- Empty `<section>` for each anchor
- `site.css` + `site.js` wired in

### 02 — Hero
- Headline: *Multi-tenant EKS — one cluster, many teams, safe by default.*
- Tagline (3-beat): *Provision with Terraform · Deliver with ArgoCD · Isolate by policy.*
- CTAs: **View source** (repo) · **Architecture** (jump to §Architecture)

### 03 — The idea
- One paragraph (reuse existing copy from old `index.md`)
- Small stack chip row: EKS · Terraform · ArgoCD · Karpenter · Istio · ALBC · cert-manager · ESO · Kyverno

### 04 — Architecture
- Full-width `img/architecture.png` with caption
- 2–3 sentence explainer beneath

### 05 — Platform planes (3-card grid)
- **Compute & Storage** — Karpenter, EBS CSI, workload classes
- **Networking** — Gateway API, Istio ambient, ALBC, external-dns
- **Security & Isolation** — ESO, cert-manager, Kyverno, AppProject

### 06 — Tenant experience
- "3 pieces of info + 1 JSON file" story
- Small JSON snippet in a `<pre>` block
- Screenshot strip from `img/argocd_team_*.png`

### 07 — Docs index (3 columns)
- Tenant guides / Platform runbooks / Design & implementation
- Links to existing Markdown pages

### 08 — Polish
- Refine CSS tokens (palette, spacing, type scale)
- Refine copy pass
- Hero background treatment (subtle gradient or grid)
- Mobile check (nav toggle, card reflow)

---

## Open questions
- Accent color: reference blue, Kubernetes `#326ce5`, or AWS orange?
- Dark mode toggle: yes/no?
- Fonts: system stack, Google Fonts (Inter), or self-hosted?
