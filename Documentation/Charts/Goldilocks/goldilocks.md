# Goldilocks

---

## 1) What Goldilocks Does

Goldilocks is a tool by Fairwinds that answers one of the hardest questions in Kubernetes operations: **how much CPU and memory should I actually request for this container?**

Setting resource requests correctly is critical:
- Too **low**: the pod gets evicted under memory pressure, or throttled when the node is busy.
- Too **high**: you waste cluster capacity and inflate your cloud bill. Karpenter provisions larger nodes than necessary.

The problem is that most teams guess based on intuition, copy defaults from tutorials, or set very high limits "just in case." Neither approach is correct.

### How Goldilocks solves this

Goldilocks uses the **Vertical Pod Autoscaler Recommender** to analyze actual CPU and memory usage per container over time, then surfaces those recommendations in a clear, clean web dashboard.

```
  Running Pods (actual CPU and memory usage)
       │
       │  VPA Recommender observes usage continuously
       ▼
  VPA objects (one per Deployment, created by Goldilocks controller)
       │
       │  Goldilocks controller reads VPA recommendations
       ▼
  Goldilocks Dashboard (web UI)
       │
       ▼
  You see: for each container → "request X CPU, Y memory for Burstable / Guaranteed QoS"
```

Goldilocks does **not** automatically apply changes to your pods. It only makes recommendations. You look at the dashboard, decide what to set, and update your Helm values or manifests manually.

---

## 2) The VPA Dependency

Goldilocks depends on the **VPA Recommender** component. The Recommender is the sub-component of the Vertical Pod Autoscaler that watches pods, records resource usage, and generates recommendations. It does not change anything by itself.

### Why VPA Updater and Admission Controller are disabled

The full VPA system has three components:

| Component | What it does | This project |
|-----------|-------------|--------------|
| **Recommender** | Observes pod usage and computes recommendations | ✅ Enabled |
| **Updater** | Evicts pods that need resource updated | ❌ Disabled |
| **Admission Controller** | Intercepts new pod creation and injects resource requests | ❌ Disabled |

The Updater is disabled because it would autonomously restart your pods to apply recommendations. In a production cluster, you do not want an automated system restarting workloads without your approval. The recommendations from Goldilocks are advisory only.

The Admission Controller is disabled for a specific reason: **it causes ArgoCD sync issues**. The admission controller generates a random TLS certificate on each install. ArgoCD detects this certificate changes on every sync attempt and marks the application as OutOfSync forever — a false positive it can never resolve. Disabling it:
- Prevents ArgoCD from constantly showing sync drift.
- Removes the TLS certificate generation that causes the instability.
- Has no practical effect since we are not auto-applying recommendations anyway.

---

## 3) Values Walkthrough

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# VPA (Vertical Pod Autoscaler)
# ─────────────────────────────────────────────────────────────────────────────
# Goldilocks installs VPA as a dependency. Only the Recommender is needed.
vpa:
  enabled: true   # Install VPA as part of this chart
  
  recommender:
    enabled: true   # The core engine — observes pod usage and generates recommendations
  
  updater:
    enabled: false  # Do NOT automatically restart pods to apply recommendations
  
  admissionController:
    enabled: false  # Do NOT intercept pod creation
    # Reason: the admission controller generates a random TLS cert on each deploy.
    # ArgoCD sees the cert change as a diff on every sync and never reaches Synced state.
    # Disabling it keeps ArgoCD permanently green.

# ─────────────────────────────────────────────────────────────────────────────
# CONTROLLER
# ─────────────────────────────────────────────────────────────────────────────
# The Goldilocks controller watches namespaces and creates one VPA object
# per Deployment found in those namespaces.
controller:
  flags:
    # Option A: Monitor every namespace automatically (no labeling needed).
    # Simplest setup — good for clusters where you want global recommendations.
    on-by-default: true

    # Option B: Opt-in per namespace. Set on-by-default: false and label
    # specific namespaces instead:
    # on-by-default: false
    # include-namespaces: "robot-shop,backend,frontend"

    # Option C: Opt-out specific namespaces even when on-by-default is true:
    # exclude-namespaces: "kube-system,cert-manager,karpenter"

# ─────────────────────────────────────────────────────────────────────────────
# DASHBOARD
# ─────────────────────────────────────────────────────────────────────────────
dashboard:
  enabled: true
  replicaCount: 1
  
  service:
    type: ClusterIP
    port: 80

  # Containers to hide from the dashboard.
  # These are sidecars injected by service meshes or CNI plugins that
  # you have no control over — their recommendations are meaningless.
  excludeContainers: "linkerd-proxy,istio-proxy,aws-node,kube-proxy"

  # ── Ingress ───────────────────────────────────────────────────────────────
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    tls:
      - secretName: goldilocks-tls
        hosts:
          - "goldilocks.yourdomain.com"
    hosts:
      - host: "goldilocks.yourdomain.com"
        paths:
          - path: "/"
            type: Prefix

  # ── Resources ─────────────────────────────────────────────────────────────
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    # No limits set — the dashboard is a lightweight read-only UI
```

---

## 4) Namespace Discovery: Three Modes

### Mode 1: Global (on-by-default: true)

```yaml
controller:
  flags:
    on-by-default: true
```

The controller monitors every namespace automatically. VPA objects are created for every Deployment in the cluster. This is the simplest setup and produces the most comprehensive recommendations.

### Mode 2: Label-based opt-in (on-by-default: false)

```yaml
controller:
  flags:
    on-by-default: false
```

Then label only the namespaces you care about:

```bash
kubectl label namespace robot-shop goldilocks.fairwinds.com/enabled=true
kubectl label namespace backend goldilocks.fairwinds.com/enabled=true
```

The controller ignores all unlabeled namespaces. Useful when you want to exclude system namespaces and focus on application namespaces only.

### Mode 3: Explicit include list

```yaml
controller:
  flags:
    on-by-default: false
    include-namespaces: "robot-shop,backend,frontend,payments"
```

Named namespaces are monitored without needing manual labels. Useful in Terraform-managed clusters where namespace labels are not practical.

---

## 5) Reading the Dashboard

Open the Goldilocks dashboard at `https://goldilocks.yourdomain.com`. The dashboard shows:

```
Namespace: robot-shop
  Deployment: catalogue
    Container: catalogue
      QoS Class | CPU Request | CPU Limit | Memory Request | Memory Limit
      ─────────────────────────────────────────────────────────────────────
      Guaranteed | 15m         | 15m       | 105Mi          | 105Mi
      Burstable  | 15m         | 30m       | 105Mi          | 210Mi
```

### QoS classes explained

| QoS Class | What it means | When to use |
|-----------|--------------|-------------|
| **Guaranteed** | Request = Limit for all resources | Latency-sensitive workloads; pod is never throttled or evicted first |
| **Burstable** | Request < Limit | Most application workloads; can burst above request if node has headroom |

Goldilocks shows both QoS recommendations for every container. You pick which quality class fits the workload.

### What the numbers represent

The recommendations are based on the **observed 90th percentile memory usage** and **observed 50th percentile CPU usage** over the recent history window. The VPA Recommender adds safety margins above the observed values. These recommendations improve over time as more data is collected — the first 24–48 hours of data will produce conservative estimates that refine as usage patterns emerge.

### How to apply a recommendation

Once you see the recommended values, update the resources in your Helm values:

```yaml
# Before (guessed values):
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# After (Goldilocks Burstable recommendation):
resources:
  requests:
    cpu: 15m
    memory: 105Mi
  limits:
    cpu: 30m
    memory: 210Mi
```

This reduction allows Karpenter to provision smaller nodes, directly reducing the cluster's running cost.

---

## 6) How VPA Objects Are Created

When the Goldilocks controller discovers a monitored namespace, it creates a `VerticalPodAutoscaler` object for each Deployment:

```yaml
# Created automatically by Goldilocks controller — do not edit manually
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: catalogue
  namespace: robot-shop
  labels:
    app.kubernetes.io/managed-by: goldilocks
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: catalogue
  updatePolicy:
    updateMode: "Off"    # Never update pods — recommendations only
```

`updateMode: "Off"` is set by Goldilocks precisely because the Updater is disabled. The VPA object exists purely to feed data to the Recommender. The Recommender populates `.status.recommendation` which the dashboard reads.

---

## 7) Verifying It Works

```bash
# Check Goldilocks controller and dashboard are running
kubectl get pods -n goldilocks

# Check VPA objects were created for your namespace
kubectl get vpa -n robot-shop

# Describe one to see raw recommendations
kubectl describe vpa catalogue -n robot-shop
```

In the `describe` output, look for:
```yaml
Status:
  Recommendation:
    Container Recommendations:
    - Container Name: catalogue
      Lower Bound:
        Cpu: 15m
        Memory: 105Mi
      Target:
        Cpu: 15m
        Memory: 105Mi
      Upper Bound:
        Cpu: 100m
        Memory: 200Mi
```

`Target` is the value Goldilocks shows in the dashboard under the "Burstable" recommendation.
