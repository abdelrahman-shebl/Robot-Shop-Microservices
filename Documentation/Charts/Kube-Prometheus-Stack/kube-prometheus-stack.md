# kube-prometheus-stack

Companion file: [ServiceMonitors.md](ServiceMonitors.md)

---

## 1) What It Is

`kube-prometheus-stack` is not a single application — it is a complete, pre-wired observability platform bundled into one Helm chart. Installing it once deploys:

| Component             | What it does                                                                  |
|-----------------------|-------------------------------------------------------------------------------|
| **Prometheus Operator** | Manages Prometheus and Alertmanager instances via Kubernetes CRDs. The control plane that makes everything else work. |
| **Prometheus**        | Scrapes metrics, evaluates rules, stores time-series data                     |
| **Grafana**           | Dashboards and visualization                                                  |
| **Alertmanager**      | Routes alerts to Slack, PagerDuty, email, etc.                                |
| **Node Exporter**     | Per-node metrics (CPU, memory, disk, network) via a DaemonSet                |
| **Kube State Metrics**| Exposes Kubernetes object state (pod restarts, deployment replicas, etc.)     |
| **Prometheus Operator CRDs** | `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `AlertmanagerConfig`, etc. |

### Why the Operator pattern matters

Without the Operator, you'd configure Prometheus with a static YAML `scrape_configs` file. Every time you add a new service, you'd edit the file and restart Prometheus. The Prometheus Operator inverts this: services declare themselves as scrape targets using `ServiceMonitor` CRDs, and the Operator automatically reconciles the live Prometheus scrape configuration. New services register themselves — Prometheus never needs a manual restart.

---

## 2) The CRD Problem with ArgoCD

`kube-prometheus-stack` installs **over 20 Custom Resource Definitions** (CRDs) as part of its chart. This creates a fundamental problem with ArgoCD sync:

### Why ArgoCD fails on first sync

On first install, when ArgoCD tries to sync the chart:
1. It parses the entire YAML manifest before applying anything.
2. The manifest contains resources that *use* CRDs (e.g., `ServiceMonitor`, `PrometheusRule`).
3. The CRDs don't exist yet because they are part of the same sync.
4. Kubernetes API server rejects the resources that reference non-existent CRDs.
5. ArgoCD marks the sync as Failed.

This creates a chicken-and-egg problem: the CRDs need to exist before the chart resources are applied, but the chart installs both at once.

### Solution A: Sync Waves (used in this project)

ArgoCD sync waves let you control the order in which resources are applied within a single sync operation. The chart is split across two waves:

```yaml
# In the ArgoCD Application manifest:
syncPolicy:
  syncOptions:
    - CreateNamespace=true
    - Replace=true           # apply CRDs with --force (handles immutable fields)
    - ServerSideApply=true   # avoids "annotation too long" errors on large CRDs
```

And in the resource-level annotations:
```yaml
# On the Application managing kube-prometheus-stack:
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # deploy this before apps in wave 2, 3...
```

The key sync options for this chart:

| Option | What it does |
|--------|-------------|
| `Replace=true` | Uses `kubectl replace` instead of `apply` for CRDs — avoids "immutable field" errors on CRD updates |
| `ServerSideApply=true` | Offloads field management to the API server — required for CRDs that exceed annotation size limits |
| `SkipDryRunOnMissingResource=true` | Skips validation for resources whose CRDs don't exist yet — prevents the chicken-and-egg failure |

### Solution B: Disable CRDs in the Helm chart, install them separately

```yaml
# In prometheus values:
crds:
  enabled: false   # don't let Helm manage CRDs

# Then apply CRDs manually via an ArgoCD Application pointing to the CRDs directory:
# kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/
```

This is cleaner for large clusters but adds operational complexity.

### Solution C: Disable admission webhooks (simplest for dev/staging)

The `prometheusOperator.admissionWebhooks` component is the main source of sync failures beyond the CRD issue. Disabling it removes a significant portion of the syncing complexity at the cost of losing webhook validation:

```yaml
prometheusOperator:
  admissionWebhooks:
    enabled: false
    patch: null
  tls:
    enabled: false
```

This is what is configured in this project's `prometheus-values.yaml`. It removes the cert-injection Jobs that ArgoCD has trouble reconciling, the webhook Deployment, and the MutatingWebhookConfiguration.

---

## 3) Values Walkthrough

### Full annotated values

```yaml
# Override the chart name prefix so all resource names start with "monitor"
# instead of the default "kube-prometheus-stack-monitor" which becomes very long.
fullnameOverride: "monitor"

# ─────────────────────────────────────────────────────────────────────────────
# PROMETHEUS
# ─────────────────────────────────────────────────────────────────────────────
prometheus:
  service:
    port: 80        # Serve Prometheus UI on port 80 inside the cluster (instead of 9090)
    type: ClusterIP # Not exposed externally — Traefik/Ingress handles external access

  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - "prometheus.yourdomain.com"
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    tls:
      - secretName: prometheus-tls
        hosts:
          - "prometheus.yourdomain.com"

  prometheusSpec:
    # ── ServiceMonitor discovery configuration ──────────────────────────────
    
    # By default, Prometheus only scrapes ServiceMonitors that have a matching
    # 'release' label. Setting this to false removes that restriction entirely
    # — Prometheus will scrape ALL ServiceMonitors in the cluster.
    serviceMonitorSelectorNilUsesHelmValues: false
    
    # By default, Prometheus only looks in its own namespace for ServiceMonitors.
    # Setting this to {} (empty = all) makes it search every namespace.
    serviceMonitorNamespaceSelector: {}
    
    # Same for PodMonitors (scrape pods directly without a Service)
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorNamespaceSelector: {}

    # ── Storage ─────────────────────────────────────────────────────────────
    replicas: 1
    
    # For ephemeral/development environments, use no persistent storage.
    # Metrics are lost on pod restart.
    storageSpec: {}
    
    # For production, use a persistent volume:
    # storageSpec:
    #   volumeClaimTemplate:
    #     spec:
    #       storageClassName: gp3
    #       accessModes: ["ReadWriteOnce"]
    #       resources:
    #         requests:
    #           storage: 50Gi

    # How long to keep metrics data
    retention: 2h        # short for dev (saves disk)
    retentionSize: 500MB # also cap by size
    
    # Used for alert links and Prometheus UI external URL
    externalUrl: "https://prometheus.yourdomain.com"

# ─────────────────────────────────────────────────────────────────────────────
# GRAFANA
# ─────────────────────────────────────────────────────────────────────────────
grafana:
  adminUser: admin
  adminPassword: admin   # change in production — use a secret reference instead

  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - "grafana.yourdomain.com"
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    tls:
      - secretName: grafana-tls
        hosts:
          - "grafana.yourdomain.com"

  # Disable Grafana's default dashboards (Kubernetes cluster overview, etc.)
  # They tend to be outdated — use custom ones from grafana.com instead
  defaultDashboardsEnabled: false

  # ── Sidecar ───────────────────────────────────────────────────────────────
  # The sidecar container watches for ConfigMaps with a specific label
  # and automatically loads them into Grafana as dashboards.
  # This is the core mechanism for provisioning dashboards-as-code.
  sidecar:
    datasources:
      enabled: true
      defaultDatasourceEnabled: true   # auto-provisions Prometheus as default datasource

  # ── Dashboard Providers ───────────────────────────────────────────────────
  # Tells Grafana to look for dashboard JSON files at this path.
  # The sidecar deposits ConfigMap-sourced dashboards here.
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default   # where sidecar writes dashboards

  # ── Prebuilt Dashboards from grafana.com ──────────────────────────────────
  # These are downloaded at Grafana startup by the chart.
  # gnetId is the dashboard ID from https://grafana.com/grafana/dashboards/
  dashboards:
    default:
      node-exporter:
        gnetId: 1860        # Node Exporter Full
        revision: 31
        datasource: Prometheus
      
      k8s-cluster:
        gnetId: 7249        # Kubernetes Cluster Monitoring
        revision: 1
        datasource: Prometheus
      
      mysql-overview:
        gnetId: 7362        # MySQL Overview
        revision: 1
        datasource: Prometheus

      opencost-overview:
        gnetId: 22208       # OpenCost Overview
        revision: 1
        datasource: Prometheus

      opencost-namespace:
        gnetId: 22252       # OpenCost per-Namespace
        revision: 1
        datasource: Prometheus

# ─────────────────────────────────────────────────────────────────────────────
# PROMETHEUS OPERATOR
# ─────────────────────────────────────────────────────────────────────────────
prometheusOperator:
  # Admission webhooks validate PrometheusRule and AlertmanagerConfig resources
  # before they reach the API server. They require a TLS certificate injected
  # by a Job, which conflicts with ArgoCD's sync model.
  # Disabled here to avoid ArgoCD sync failures and removal of cert Job complexity.
  admissionWebhooks:
    enabled: false
    patch: null    # disables the cert-injection Job
  tls:
    enabled: false
```

---

## 4) Grafana Dashboards: Two Approaches

Grafana dashboards can be provisioned in two ways. Both can be used at the same time.

### Approach A: grafana.com IDs (via `dashboards:` in values)

The chart downloads the dashboard JSON at pod startup:

```yaml
grafana:
  dashboards:
    default:
      my-dashboard:
        gnetId: 1860    # https://grafana.com/grafana/dashboards/1860
        revision: 31
        datasource: Prometheus
```

**Pros:** zero maintenance — always available.  
**Cons:** requires internet access at pod startup; cannot customize the JSON.

---

### Approach B: Custom ConfigMap (via sidecar)

This is the right approach for custom or modified dashboards. Grafana runs a sidecar container (`k8s-sidecar`) that watches for ConfigMaps labeled `grafana_dashboard: "1"` across all namespaces, copies the JSON into the dashboards directory, and hot-reloads Grafana — no restart needed.

**Step 1: Enable the sidecar (already enabled in values above)**

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard         # sidecar looks for this label on ConfigMaps
      labelValue: "1"                  # the value to match
      searchNamespace: ALL             # search all namespaces, not just grafana's
      folder: /var/lib/grafana/dashboards/default
```

**Step 2: Create a ConfigMap in any namespace**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-custom-dashboard
  namespace: monitoring          # can be any namespace
  labels:
    grafana_dashboard: "1"       # must match the label Grafana sidecar watches for
data:
  my-dashboard.json: |           # key name is the filename; must end in .json
    {
      "__inputs": [],
      "__requires": [],
      "annotations": { "list": [] },
      "editable": true,
      "gnetId": null,
      "graphTooltip": 0,
      "id": null,
      "panels": [
        {
          "type": "graph",
          "title": "HTTP Requests Per Second",
          "targets": [
            {
              "expr": "rate(http_requests_total[5m])",
              "legendFormat": "{{service}}"
            }
          ]
        }
      ],
      "title": "My Custom Dashboard",
      "uid": "my-custom-uid-001"
    }
```

**Step 3: The sidecar picks it up automatically**

Within a few seconds of creating (or updating) this ConfigMap, the sidecar:
1. Detects the label `grafana_dashboard: "1"`.
2. Copies `my-dashboard.json` to `/var/lib/grafana/dashboards/default/`.
3. Grafana reloads dashboards.
4. Your dashboard appears in Grafana under the default folder.

**Mixing both approaches is fine.** Prebuilt community dashboards via `gnetId` coexist with custom ConfigMap dashboards. Both land in the same folder.

---

## 5) ServiceMonitor Discovery

The most common configuration mistake with kube-prometheus-stack is that Prometheus does not pick up ServiceMonitors deployed by other Helm charts. This happens because of a selector mismatch.

### The problem

By default, Prometheus only picks up ServiceMonitors that have a label matching the Helm release name:
```
release: monitor
```

A MySQL exporter chart deployed separately will create a ServiceMonitor without that label — so Prometheus ignores it.

### The fix (already applied in this project)

```yaml
prometheusSpec:
  serviceMonitorSelectorNilUsesHelmValues: false   # remove the 'release' label requirement
  serviceMonitorNamespaceSelector: {}              # search ALL namespaces
```

With this configuration, Prometheus discovers every ServiceMonitor in the entire cluster, regardless of labels or namespace. This is the recommended setup for multi-namespace clusters.

### How to verify which targets Prometheus is scraping

```bash
# Port-forward or visit the Prometheus UI:
kubectl port-forward -n monitoring svc/monitor-prometheus 9090:80

# Then open: http://localhost:9090/targets
# You'll see all active scrape targets and their status (UP/DOWN)
```

---

## 6) Useful Prometheus Queries

```promql
# All pods, by namespace
count(kube_pod_info) by (namespace)

# CPU usage per node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage per pod
container_memory_working_set_bytes{container!=""}

# HTTP error rate (requires ServiceMonitor scraping your apps)
rate(http_requests_total{status=~"5.."}[5m])

# Karpenter: nodes by pool and capacity type
karpenter_nodes_total
```

---

## 7) Production Settings Worth Changing

| Setting | Dev value | Production recommendation |
|---------|-----------|---------------------------|
| `prometheusSpec.retention` | `2h` | `15d` or `30d` |
| `prometheusSpec.storageSpec` | `{}` (none) | gp3 PVC, 50–200Gi |
| `prometheusSpec.replicas` | `1` | `2` (HA) |
| `grafana.adminPassword` | `admin` | Use `grafana.admin.existingSecret` |
| `prometheusOperator.admissionWebhooks.enabled` | `false` | `true` in stable GitOps pipelines |

### Production Grafana password from a Kubernetes secret

```yaml
grafana:
  admin:
    existingSecret: "grafana-admin-secret"   # secret must exist before chart installs
    userKey: "admin-user"
    passwordKey: "admin-password"
```
