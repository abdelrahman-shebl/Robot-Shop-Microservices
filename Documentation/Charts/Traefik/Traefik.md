# Traefik
---

## 1) What Traefik Does

Traefik is a reverse proxy and Kubernetes Ingress controller. It acts as the cluster's front door — all external traffic enters through Traefik, which routes it to the right service based on hostname and path rules.

Without Traefik (or another ingress controller):
- Kubernetes `Ingress` objects do nothing — they are just metadata,
- each service would need its own AWS Load Balancer (expensive and unmanageable).

With Traefik:
- one AWS Load Balancer is created for the entire cluster,
- Traefik watches `Ingress` objects and routes traffic accordingly,
- TLS termination happens at Traefik using certificates from cert-manager,
- HTTP to HTTPS redirect is handled centrally.

```
Internet
   │
   ▼
AWS Load Balancer (one per cluster)
   │
   ▼
Traefik (Ingress Controller)
   │
   ├──► argocd.example.com   →  argocd namespace
   ├──► grafana.example.com  →  monitoring namespace
   ├──► app.example.com      →  robotshop namespace
   └──► ...
```

---

## 2) Chart Reference

| Field        | Value                                                    |
|--------------|----------------------------------------------------------|
| Chart name   | `traefik`                                                |
| Helm repo    | `https://traefik.github.io/charts`                       |
| ArtifactHub  | https://artifacthub.io/packages/helm/traefik/traefik     |
| Version used | `39.0.0`                                                 |

---

## 3) Helm Values Walkthrough

Chart: `traefik` from `https://traefik.github.io/charts`

```yaml
# Define the entry points (listening ports)
ports:
  web:
    port: 80       # HTTP entry point — immediately redirects to HTTPS
  websecure:
    port: 443      # HTTPS entry point — where actual traffic is served

# Create an AWS LoadBalancer Service for Traefik
service:
  enabled: true
  type: LoadBalancer    # creates an AWS Classic or NLB depending on annotations

# HTTP to HTTPS redirect — applied globally at the entry point level
# Any request coming in on port 80 is permanently redirected to port 443
additionalArguments:
  - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
  - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
  - "--entrypoints.web.http.redirections.entrypoint.permanent=true"

# No local disk persistence needed
# cert-manager stores TLS certificates as Kubernetes Secrets, not on disk
persistence:
  enabled: false
```

### How to adjust values from this base

**Add resource limits:**
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Run on the system node (if using taints):**
```yaml
tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"
```

**Set replica count:**
```yaml
deployment:
  replicas: 2
```

**Use an NLB instead of Classic Load Balancer:**
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

**Expose the Traefik dashboard (for debugging):**
```yaml
ingressRoute:
  dashboard:
    enabled: true
```

**Enable access logs:**
```yaml
logs:
  access:
    enabled: true
```

**Disable HTTP to HTTPS redirect (if handling redirect elsewhere):**
Remove the `additionalArguments` block entirely.

---

## 4) Ingress Class Name

When creating a Kubernetes `Ingress`, the `ingressClassName` tells Kubernetes which ingress controller should handle it.

Traefik registers itself as `traefik`.

```yaml
spec:
  ingressClassName: traefik
```

Without this field, the Ingress may be ignored (if multiple controllers exist) or picked up by the wrong one.

---

## 5) Annotations for Common Behaviors

Annotations on `Ingress` objects control Traefik-specific routing behavior.

### Route traffic over HTTPS only (most common)

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
```

This tells Traefik to only attach this route to the `websecure` (port 443) entry point.

---

### HTTPS backend (when the upstream service itself uses HTTPS)

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/backend-protocol: "https"
```

Use this when forwarding traffic to a service that listens on HTTPS internally (e.g., ArgoCD in non-insecure mode).

In this setup ArgoCD runs in `insecure: true` mode, so the backend protocol is `http`:

```yaml
    traefik.ingress.kubernetes.io/backend-protocol: "http"
```

---

### Enable both HTTP and HTTPS entry points

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
```

Only needed if the service must respond on both ports (unusual — the global HTTP redirect already handles this).

---

### Attach a cert-manager TLS certificate

```yaml
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls       # must match Certificate.spec.secretName
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

The `secretName` must match the `secretName` in the `Certificate` object that cert-manager manages.

---

## 6) Full Ingress Example

This is a complete, working Ingress for a service exposed with TLS managed by cert-manager:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-namespace
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/backend-protocol: "http"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls          # the Secret cert-manager creates
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app-service
                port:
                  number: 8080
```

---

## 7) How Traefik, Cert-Manager, and External DNS Work Together

All three tools form the public access stack:

```
1. cert-manager issues TLS certificate → stores as Kubernetes Secret
2. Traefik reads the Secret and serves HTTPS on websecure entry point
3. External DNS reads the Ingress hostname → creates Route53 A/CNAME record

Result: domain resolves → hits Traefik → TLS presented → traffic routed to service
```

Order of operations (sync waves):
- wave `-5`: cert-manager chart (CRDs installed)
- wave `-4`: cert-manager manifests (ClusterIssuer + Certificates)
- wave `-3`: Traefik, External DNS (depend on certificates existing)
- wave `0`:  app workloads (depend on routing being ready)

---

## 8) How ArgoCD Deploys Traefik

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
      targetRevision: "39.0.0"
      helm:
        valueFiles:
          - $repo/terraform/modules/addons/values/traefik-values.yaml
    - repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
      targetRevision: "feature/pipeline"
      ref: repo
  destination:
    namespace: traefik
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-3"
```

- deploys at wave `-3` — after cert-manager is ready, alongside External DNS,
- values file lives in the repo, referenced via the `$repo` multi-source alias,
- `CreateNamespace=true` creates the `traefik` namespace if it does not exist.
