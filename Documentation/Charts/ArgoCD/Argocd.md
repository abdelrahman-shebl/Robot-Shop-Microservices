# ArgoCD

Companion file:
- [Argocd-apps.md](Argocd-apps.md)

---

## 1) What ArgoCD Does

ArgoCD is a GitOps continuous delivery tool for Kubernetes.

The core idea:
- a Git repository is the single source of truth for what should be deployed,
- ArgoCD continuously watches that repository,
- if the live cluster state drifts from the Git state, ArgoCD detects it and can automatically or manually reconcile it.

Without ArgoCD, applying changes means running `kubectl apply` or `helm upgrade` manually.
With ArgoCD, pushing to Git is enough — the cluster self-heals to match the repository.

---

## 2) ArgoCD Architecture

ArgoCD is made of five internal components. Each has a distinct role.

```
                     Git Repository
                          │
                          ▼
              ┌─────────────────────┐
              │     Repo Server     │  ← clones Git, renders Helm/Kustomize
              └─────────────────────┘
                          │
              ┌─────────────────────┐
              │     Redis Cache     │  ← caches rendered manifests
              └─────────────────────┘
                          │
              ┌─────────────────────┐
              │    App Controller   │  ← compares Git vs live cluster
              └─────────────────────┘
                      │       │
           sync ◄─────┘       └─────► Kubernetes API
              ┌─────────────────────┐
              │    ArgoCD Server    │  ← UI, CLI, API gateway
              └─────────────────────┘
              ┌─────────────────────┐
              │   ApplicationSet   │  ← generates Applications from templates
              └─────────────────────┘
```

---

## 3) Component Deep Dive

### Repo Server

**What it does:**
- clones Git repositories,
- runs `helm template` or Kustomize to render final Kubernetes YAML,
- sends rendered manifests to the Controller.

**Why it needs resources:**
- runs `helm template` for every application on every sync check,
- under heavy load (many apps, large charts), CPU and memory spike,
- autoscaling is recommended to handle burst deploys.

```yaml
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 3
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 1Gi
```

This is the most resource-variable component — size limits generously.

---

### Application Controller

**What it does:**
- watches all Applications in the cluster,
- continuously compares live Kubernetes state vs the rendered Git state,
- triggers sync when drift is detected (if automated sync is enabled).

**Why it needs resources:**
- holds in-memory state for every managed resource across all applications,
- uses the Kubernetes API heavily (watch + list calls),
- memory grows with the number of managed resources.

```yaml
controller:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi
```

This is the brain of ArgoCD — give it the most memory of all components.

---

### ArgoCD Server (UI)

**What it does:**
- serves the web UI and the ArgoCD CLI API,
- handles login, application views, and manual sync triggers,
- mostly idle between user interactions.

**Why it needs fewer resources:**
- it only proxies API calls and renders the UI,
- compute load is proportional to active user sessions.

```yaml
server:
  replicas: 1
  resources:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  insecure: true  # TLS is terminated at Traefik, not here
```

---

### Redis

**What it does:**
- caches the rendered manifests and Kubernetes state snapshots,
- prevents the Repo Server from re-running `helm template` on every health check,
- speeds up the Controller's comparison loop.

```yaml
redis:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

Redis only caches data in memory — it does not need disk and stays small.

---

### ApplicationSet Controller

**What it does:**
- generates multiple Application resources from a single template,
- useful for deploying the same chart to many clusters or environments automatically.

```yaml
applicationSet:
  replicas: 1
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
```

ApplicationSet is lightweight — it only generates YAML objects, it does not sync them.

---

## 4) Resource Summary Table

| Component         | CPU Priority | Memory Priority | Why                                          |
|-------------------|:------------:|:---------------:|----------------------------------------------|
| Repo Server       | High         | High            | renders Helm charts on every sync check      |
| App Controller    | Medium       | Highest         | holds state for all managed resources        |
| ArgoCD Server     | Low          | Low             | mostly idle, UI and CLI proxy only           |
| Redis             | Low          | Low             | small cache, stateless between restarts      |
| ApplicationSet    | Very Low     | Very Low        | only generates Application objects           |

---

## 5) Full `argo-values.tpl` Walkthrough

This file is passed to the `argo-cd` Helm chart via Terraform's `templatefile()`.

### Redis block

```yaml
redis:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

Small, fixed size. Rarely needs tuning.

---

### Repo Server block

```yaml
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 3
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 1Gi
```

Autoscaling handles burst when all apps sync at startup. Limits are generous because `helm template` is CPU-intensive.

---

### Controller block

```yaml
controller:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
```

- `metrics.enabled: true` exposes Prometheus metrics on `/metrics`,
- `serviceMonitor.enabled: false` disables automatic Prometheus scraping (enable when kube-prometheus-stack is running).

---

### Server block

```yaml
server:
  replicas: 1
  insecure: true
  ingress:
    enabled: true
    hostname: argocd.${domain}
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    tls: true
    extraTls:
      - hosts:
          - argocd.${domain}
        secretName: argocd-tls
    https: false
```

- `insecure: true` — ArgoCD Server listens on plain HTTP. Traefik handles HTTPS termination.
- `ingress.hostname` — the public URL of the ArgoCD UI,
- `tls: true` + `extraTls.secretName` — Traefik routes HTTPS and presents a cert-manager TLS certificate,
- `https: false` — tells ArgoCD's Ingress backend to use HTTP (port 80), not redirect to HTTPS internally.

---

### Configs block

```yaml
configs:
  params:
    server.insecure: true
  cm:
    url: https://argocd.${domain}
  secret:
    argocdServerAdminPassword: "$2a$10$..."
```

- `server.insecure: true` — matches the server-level `insecure` flag, required for Traefik TLS termination,
- `cm.url` — the canonical public URL, used in notifications and SSO redirects,
- `argocdServerAdminPassword` — bcrypt hash of the admin password set at install time.

---

### Global tolerations block

```yaml
global:
  tolerations:
    - key: "workload-type"
      operator: "Equal"
      value: "system"
      effect: "NoSchedule"
```

ArgoCD pods are scheduled only on nodes tainted with `workload-type=system:NoSchedule`.
This keeps ArgoCD on dedicated system nodes, away from application workloads.

---

## 6) How Terraform Deploys ArgoCD

In `main.tf`:

```hcl
resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.4.1"
  namespace        = "argocd"
  create_namespace = true

  values = [
    templatefile("${path.module}/values/argo-values.tpl", {
      domain = var.domain
    })
  ]
}
```

- `templatefile()` renders `argo-values.tpl` using Terraform variables before passing it to Helm,
- `${domain}` becomes the actual domain name in ingress hostnames and config URLs,
- only `domain` is injected into this values file — other values are static.

---

## 7) Next File

For how ArgoCD Applications are defined and managed (syncing charts, manifests, and custom repos), continue with:

- [Argocd-apps.md](Argocd-apps.md)
