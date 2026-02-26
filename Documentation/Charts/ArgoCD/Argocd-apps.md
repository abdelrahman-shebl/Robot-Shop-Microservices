# ArgoCD Apps

Companion file:
- [Argocd.md](Argocd.md)

---

## 1) What `argocd-apps` Does

`argocd-apps` is a Helm chart that creates ArgoCD `Application` resources.

Instead of manually writing and applying each `Application` YAML to the cluster, this chart generates them from a structured `values.yaml`. Terraform installs the chart and passes in the application definitions as values.

Each entry in `argo-apps-values.tpl` becomes one ArgoCD `Application` — a GitOps deployment unit that ArgoCD watches, syncs, and self-heals.

---

## 2) Application Entry Structure

Every application entry follows this skeleton:

```yaml
applications:
  <app-name>:
    namespace: argocd          # namespace where the Application resource lives
    project: default           # ArgoCD project (access control grouping)
    syncPolicy: ...            # when and how to sync
    source: ...                # single source (chart or repo path)
    sources: ...               # multi-source (chart + values from repo)
    destination:
      namespace: <target-ns>   # where resources are deployed on the cluster
      server: https://kubernetes.default.svc
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "0"  # order of operations
```

- `namespace: argocd` — always `argocd` (where the Application resource itself lives),
- `destination.namespace` — the target namespace on the cluster for the deployed resources,
- `project: default` — groups applications for RBAC; `default` allows everything.

---

## 3) syncPolicy Options

`syncPolicy` controls when ArgoCD syncs and what it does during sync.

### Automated sync

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

- `automated` — ArgoCD syncs automatically, no manual trigger needed,
- `prune: true` — resources removed from Git are also deleted from the cluster,
- `selfHeal: true` — if someone manually changes a resource on the cluster, ArgoCD reverts it back to Git state.

Without `automated`, ArgoCD only shows drift but waits for a manual sync.

---

### syncOptions flags

`syncOptions` is a list of fine-grained behaviors applied during each sync.

```yaml
syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
  - SkipDryRunOnMissingResource=true
```

#### `CreateNamespace=true`

ArgoCD creates the destination namespace if it does not exist.
Use this whenever the app targets a namespace that is not pre-created.

#### `ServerSideApply=true`

Uses Kubernetes Server-Side Apply instead of the default client-side apply.

Needed when:
- resources have large annotations that exceed client-side apply limits,
- CRDs have fields managed by multiple controllers (common with Prometheus CRDs and kube-prometheus-stack).

Without this, kube-prometheus-stack and similar charts often fail with annotation size errors.

#### `SkipDryRunOnMissingResource=true`

Skips the pre-sync dry-run validation for resources whose CRD does not exist yet.

Needed when:
- the application deploys CRD-based resources (like ESO `ExternalSecret`, Kyverno `Policy`),
- the CRD is being installed by a different application that may not be ready yet,
- without this flag, ArgoCD fails the sync with "unknown resource type" before the CRD lands.

---

### Retry block

```yaml
syncPolicy:
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

Used when a sync may fail temporarily (waiting for a CRD or a dependency to become ready).
- `limit` — maximum number of retry attempts,
- `backoff.factor: 2` — each retry waits twice as long as the previous one,
- `maxDuration` — caps the maximum wait between retries.

Example use case: `kyverno-manifests` must wait for `kyverno` CRDs to be fully installed before its policies can apply.

---

## 4) Sync Waves (Ordering)

Sync waves control the order ArgoCD deploys applications.

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
```

Lower number = deploys first.

| Wave | Purpose                                       | Examples                          |
|------|-----------------------------------------------|-----------------------------------|
| -3   | Core infrastructure (certs, secrets, ingress) | cert-manager, ESO, Traefik        |
| -2   | Monitoring and policy stack                   | kube-prometheus-stack, kyverno    |
| -1   | CRD-dependent manifests                       | kyverno-manifests, ESO manifests  |
| 0    | Application workloads                         | robot-shop                        |

Waves prevent deploying a policy engine before its CRDs exist, or deploying an app before its secrets provider is ready.

---

## 5) Three Deployment Patterns

### Pattern A: Deploy a public Helm chart

Use `sources` with a chart reference and a values file from the repo.

```yaml
traefik:
  namespace: argocd
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  sources:
    - chart: traefik
      repoURL: https://traefik.github.io/charts
      targetRevision: "32.0.0"
      helm:
        valueFiles:
          - $repo/terraform/modules/addons/values/traefik-values.yaml
    - repoURL: https://github.com/your-org/your-repo.git
      targetRevision: "main"
      ref: repo                 # gives the alias $repo to this source
  destination:
    namespace: traefik
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-3"
```

How the two sources work together:
- source 1: the public Helm chart (the actual chart to deploy),
- source 2: the Git repo (provides the values file via `$repo` alias),
- `$repo` in `valueFiles` points to the second source's checkout.

This pattern separates chart versioning from values management.

---

### Pattern B: Deploy plain Kubernetes manifests from a repo path

Use `source` (single) pointing to a directory in the Git repo.

```yaml
grafana-dashboards:
  namespace: argocd
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  source:
    path: K8s/grafana              # folder in the repo
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: "main"
  destination:
    namespace: monitoring
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-3"
```

ArgoCD applies every YAML file found under `K8s/grafana/` to the `monitoring` namespace.
No Helm rendering — plain `kubectl apply` behavior.

---

### Pattern C: Deploy a custom Helm chart from the repo

Use `sources` with a `path` source pointing to the chart directory in the repo.

```yaml
robot-shop:
  namespace: argocd
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  sources:
    - path: helm/robot-shop               # custom chart in the repo
      repoURL: https://github.com/your-org/your-repo.git
      targetRevision: "main"
      helm:
        valueFiles:
          - $repo/helm/robot-shop/values.yaml
          - $repo/helm/robot-shop/values-${env}.yaml
        parameters:
          - name: "image.tag"
            value: "latest"
    - repoURL: https://github.com/your-org/your-repo.git
      targetRevision: "main"
      ref: repo
  destination:
    namespace: robotshop
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "0"
```

`path: helm/robot-shop` points ArgoCD to the umbrella chart directory in the repo.
`valueFiles` stacks a base values file and an environment-specific override.

---

## 6) Surgical Overrides with `parameters`

When a chart value needs to be set dynamically (from Terraform variables), use `parameters` instead of rewriting the values file.

```yaml
helm:
  valueFiles:
    - $repo/terraform/modules/addons/values/opencost-values.yaml
  parameters:
    - name: "opencost.ui.ingress.hosts[0].host"
      value: "opencost.${domain}"
    - name: "opencost.ui.ingress.tls[0].hosts[0]"
      value: "opencost.${domain}"
```

- `valueFiles` sets the base configuration (static, lives in the repo),
- `parameters` injects per-environment values at deploy time (domain name, cluster name, secrets),
- parameters take higher priority than `valueFiles`.

This avoids putting environment-specific values inside the shared repo values file.

---

## 7) CRD + Manifests Pattern

Many tools split into two Applications: one that installs the chart (which includes CRDs), and one that deploys the CRD-based resources (manifests).

### Step 1: Install the chart (installs CRDs)

```yaml
kyverno:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true      # needed for Kyverno CRDs
  sources:
    - chart: kyverno
      repoURL: https://kyverno.github.io/kyverno/
      targetRevision: "3.7.0"
      helm:
        valueFiles:
          - $repo/terraform/modules/addons/values/kyverno-values.yaml
    - <<: *repo_link
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-2"    # installs first
```

### Step 2: Deploy the CRD-based resources (policies, secrets, etc.)

```yaml
kyverno-manifests:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true    # CRDs may not exist at dry-run time
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  source:
    path: K8s/kyverno
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: "main"
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-1"    # deploys after chart
```

Why this works:
- wave `-2` deploys the chart and installs CRDs,
- wave `-1` deploys the manifests after CRDs are ready,
- `SkipDryRunOnMissingResource=true` handles any timing edge where the dry-run runs before a CRD is fully registered,
- `retry` covers the remaining race condition window.

This same pattern applies to:
- ESO (`external-secrets-operator` + `external-secrets-manifests`),
- cert-manager (`cert-manager` + `cert-manager-manifests`),
- any tool that installs CRDs and then requires resources using those CRDs.

---

## 8) How Terraform Deploys ArgoCD-Apps

In `main.tf`:

```hcl
resource "helm_release" "argocd-apps" {
  name                       = "argocd-apps"
  repository                 = "https://argoproj.github.io/argo-helm"
  chart                      = "argocd-apps"
  version                    = "2.0.4"
  disable_openapi_validation = true
  depends_on                 = [helm_release.argocd]

  namespace        = "argocd"
  create_namespace = true

  values = [
    templatefile("${path.module}/values/argo-apps-values.tpl", {
      node_role              = var.node_role
      env                    = var.env
      domain                 = var.domain
      cluster_name           = var.cluster_name
      region                 = var.region
      cloudIntegrationSecret = var.cloudIntegrationSecret
    })
  ]
}
```

- `disable_openapi_validation = true` — ArgoCD Application CRDs are not in the standard OpenAPI schema, so Terraform's schema validation is disabled,
- `depends_on` — ensures ArgoCD itself is running before the Applications are created,
- `templatefile()` renders `${env}`, `${domain}`, etc. into the values file before Helm processes it,
- all dynamic values (domain, cluster name, environment, secrets) are injected here.

---

## 9) Quick Reference: When to Use Which Option

| Situation                                    | Option to add                         |
|----------------------------------------------|---------------------------------------|
| Namespace doesn't exist yet                  | `CreateNamespace=true`                |
| Chart has large CRDs (Prometheus, Kyverno)   | `ServerSideApply=true`                |
| Deploying resources whose CRD just installed | `SkipDryRunOnMissingResource=true`    |
| CRD race condition at startup                | `retry` block with backoff            |
| Need ordered deployment across apps          | `sync-wave` annotation                |
| Dynamic per-environment values               | `parameters` block                    |
| Base static config                           | `valueFiles` pointing to repo path    |
| Manual sync only (no auto-deploy)            | omit `automated` from `syncPolicy`    |
| Remove deleted resources from cluster        | `prune: true` under `automated`       |
| Prevent manual cluster edits                 | `selfHeal: true` under `automated`    |
