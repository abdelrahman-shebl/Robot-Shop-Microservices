# Kube-Prometheus-Stack Chart Guide

## Overview
The `kube-prometheus-stack` is a comprehensive monitoring solution that deploys Prometheus, Grafana, and AlertManager along with exporters and other monitoring components. It provides complete observability for your Kubernetes cluster.

**What it includes:**
- **Prometheus**: Time-series database for metrics collection and querying
- **Grafana**: Visualization and dashboarding platform
- **AlertManager**: Alert routing and management
- **Prometheus Operator**: Manages Prometheus instances via CRDs
- **Node Exporter**: Collects host metrics
- **kube-state-metrics**: Exports Kubernetes object metrics
- **Prometheus Blackbox Exporter**: Network and HTTP probe monitoring

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│           Kube-Prometheus-Stack Deployment             │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐    ┌──────────────┐   ┌──────────┐   │
│  │  Prometheus  │←→──│   AlertMgr   │   │ Grafana  │   │
│  └──────────────┘    └──────────────┘   └──────────┘   │
│         ↑                                       ↑        │
│         │ Scrapes metrics from                 │        │
│         └───────────────────┬──────────────────┘        │
│                             │                           │
│  ┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │
│  │ ServiceMonitors (Auto-discovery via CRDs)      │   │
│  │ - Node Exporter, kube-state-metrics, etc.      │   │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Values Explanation

### 1. **Global Configuration**

```yaml
kube-prometheus-stack:
  fullnameOverride: "monitor"  # Makes release name "monitor" instead of "kube-prometheus-stack-monitor"
  enabled: true                # Enable the entire stack
```

**Purpose**: Simplifies resource naming and makes Kubernetes objects easier to reference.

---

### 2. **Prometheus Configuration**

#### **Service Configuration**
```yaml
prometheus:
  service:
    port: 80                # External port users access via Ingress
    targetPort: 9090        # Internal Prometheus API port
    type: ClusterIP         # Internal access only (not exposed directly)
```

**Why these values:**
- `port: 80`: Traefik routes traffic to port 80, avoiding the need for `:9090` in URLs
- `targetPort: 9090`: Standard Prometheus internal API port
- `ClusterIP`: Secure - only accessible via Ingress with authentication

**Modification Guide:**
```yaml
# For production with high traffic:
prometheus:
  service:
    port: 80
    targetPort: 9090
    type: ClusterIP
    # Add load balancer affinity (optional)
```

---

#### **Ingress Configuration**
```yaml
prometheus:
  ingress:
    enabled: true
    ingressClassName: traefik    # Points to Traefik ingress controller
    
    hosts: 
      - prometheus.yourdomain.com  # Your custom domain
    
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    
    tls: 
      - secretName: prometheus-tls
        hosts:
          - prometheus.yourdomain.com
```

**How to modify as template:**
```yaml
prometheus:
  ingress:
    enabled: true
    ingressClassName: traefik
    
    hosts: 
      - "{{ .Values.prometheus.domainName }}"
    
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    
    tls: 
      - secretName: prometheus-tls
        hosts:
          - "{{ .Values.prometheus.domainName }}"
```

**Then in your values file:**
```yaml
prometheus:
  domainName: prometheus.yourdomain.com
```

---

#### **PrometheusSpec - The Core Configuration**

```yaml
prometheusSpec:
  # 1. SERVICE MONITOR SELECTION
  serviceMonitorSelectorNilUsesHelmValues: false
  # ↓ WHAT THIS DOES:
  # - true (default): Only discovers ServiceMonitors with release label matching Helm release
  # - false: Discovers ALL ServiceMonitors in the cluster (we want this!)
  
  # 2. NAMESPACE SCOPE
  serviceMonitorNamespaceSelector: {}
  # ↓ WHAT THIS DOES:
  # - {} (empty): Search across ALL namespaces
  # - Add matchLabels to restrict to specific namespaces
  
  # Example to restrict to specific namespaces:
  serviceMonitorNamespaceSelector:
    matchLabels:
      monitoring: enabled  # Only namespaces with this label
  
  # 3. POD MONITORS (Optional)
  podMonitorSelectorNilUsesHelmValues: false
  podMonitorNamespaceSelector: {}
```

**Why these settings matter:**
```yaml
# DEFAULT (DANGEROUS) - Only monitors what Prometheus Operator deployed
serviceMonitorSelectorNilUsesHelmValues: true
# Result: Won't find mysql-exporter, mongodb-exporter unless they have the release label

# OUR SETTING (COMPREHENSIVE) - Discovers all ServiceMonitors
serviceMonitorSelectorNilUsesHelmValues: false
# Result: Automatically finds and monitors:
# - prometheus-mysql-exporter ServiceMonitor
# - prometheus-mongodb-exporter ServiceMonitor
# - Any custom ServiceMonitor you create
```

---

#### **Storage & Retention**
```yaml
prometheusSpec:
  replicas: 1              # Number of Prometheus instances
  storageSpec: {}          # No persistent volume (ephemeral)
  retention: 2h            # Keep metrics for 2 hours
  retentionSize: 500MB     # Delete old metrics when storage exceeds 500MB
  externalUrl: https://prometheus.yourdomain.com  # For alert links
```

**Production Template:**
```yaml
prometheusSpec:
  replicas: 2              # High availability
  
  storageSpec:
    volumeClaimTemplate:
      spec:
        storageClassName: gp3
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 50Gi
  
  retention: 30d           # 30 days of metrics
  retentionSize: 45Gi      # Stop at 45GB
```

---

### 3. **Grafana Configuration**

```yaml
grafana:
  adminUser: admin              # Login username
  adminPassword: admin          # Login password (CHANGE IN PRODUCTION!)
  
  # Disable default dashboards and add curated ones
  defaultDashboardsEnabled: false
```

#### **Ingress for Grafana**
```yaml
grafana:
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - grafana.yourdomain.com
    
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    
    tls: 
      - secretName: grafana-tls
        hosts:
          - grafana.yourdomain.com
```

**Template Approach:**
```yaml
# In a configurable values section:
grafana:
  # Simple config
  adminUser: "{{ .Values.grafana.admin.user }}"
  adminPassword: "{{ .Values.grafana.admin.password }}"
  
  ingress:
    hosts:
      - "{{ .Values.grafana.domainName }}"
```

---

#### **Grafana Dashboards**

```yaml
grafana:
  dashboards:
    default:
      # Format: name: { gnetId: <ID>, revision: <REV>, datasource: Prometheus }
      
      node-exporter:
        gnetId: 1860
        revision: 31
        datasource: Prometheus
      # Why 1860? It's the most popular Node Exporter dashboard on Grafana.com
      
      k8s-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      # Kubernetes cluster overview dashboard
      
      mysql-overview:
        gnetId: 7362
        revision: 1
        datasource: Prometheus
      # MySQL-specific metrics (works with prometheus-mysql-exporter)
      
      mongodb:
        gnetId: 2583
        revision: 1
        datasource: Prometheus
      # MongoDB metrics dashboard
```

**How to find custom dashboards:**
1. Visit https://grafana.com/grafana/dashboards/
2. Search for your component (e.g., "PostgreSQL", "Redis")
3. Copy the gnetId from the URL
4. Add to values.yaml

**Example - Adding a PostgreSQL dashboard:**
```yaml
grafana:
  dashboards:
    default:
      postgresql:
        gnetId: 9628
        revision: 2
        datasource: Prometheus
```

---

### 4. **Integrating with MySQL & MongoDB Exporters**

The stack includes dedicated exporters configured as `ServiceMonitor` resources. This section explains how Prometheus auto-discovers them.

#### **How Discovery Works:**

```
Prometheus Operator watches for ServiceMonitor CRDs
                    ↓
Finds prometheus-mysql-exporter ServiceMonitor
                    ↓
Prometheus scrapes the exporter's metrics endpoint
                    ↓
Metrics flow into Prometheus database
                    ↓
Grafana queries Prometheus and displays on dashboards
```

#### **ServiceMonitor Creation:**

The `prometheus-mysql-exporter` and `prometheus-mongodb-exporter` charts automatically create ServiceMonitor resources that expose their metrics. This happens because:

```yaml
# In prometheus-mysql-exporter values:
serviceMonitor:
  enabled: true  # Creates a ServiceMonitor CRD

# In prometheus-mongodb-exporter values:
serviceMonitor:
  enabled: true  # Creates a ServiceMonitor CRD
```

Prometheus finds them because we set:
```yaml
serviceMonitorSelectorNilUsesHelmValues: false
```

---

## Network Policies Integration

### Adding Pod Labels for Network Policy Control

Your values.yaml already includes labels on exporters:

```yaml
prometheus-mysql-exporter:
  podLabels:
    app: mysql-exporter  # Label for network policies

prometheus-mongodb-exporter:
  podLabels:
    app: mongodb-exporter  # Label for network policies
```

**Why this matters for network policies:**

```yaml
# Example NetworkPolicy to allow only Prometheus to scrape MySQL exporter:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mysql-exporter-scrape
  namespace: robot-shop
spec:
  podSelector:
    matchLabels:
      app: mysql-exporter  # ← Uses this label
  
  policyTypes:
    - Ingress
  
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: prometheus  # Only Prometheus can scrape
      ports:
        - protocol: TCP
          port: 9104  # MySQL exporter metrics port
```

---

## Configuration Examples

### Example 1: Development Setup (Ephemeral)
```yaml
kube-prometheus-stack:
  fullnameOverride: "monitor"
  enabled: true
  
  prometheus:
    service:
      port: 80
      targetPort: 9090
      type: ClusterIP
    
    prometheusSpec:
      replicas: 1
      storageSpec: {}  # No persistent storage
      retention: 2h
      retentionSize: 500MB
      serviceMonitorSelectorNilUsesHelmValues: false
      serviceMonitorNamespaceSelector: {}
```

### Example 2: Production Setup (Persistent)
```yaml
kube-prometheus-stack:
  fullnameOverride: "monitor"
  enabled: true
  
  prometheus:
    service:
      port: 80
      targetPort: 9090
      type: ClusterIP
    
    prometheusSpec:
      replicas: 3  # HA
      
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: gp3
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 100Gi
      
      retention: 30d
      retentionSize: 90Gi
      
      # High cardinality settings
      serviceMonitorSelectorNilUsesHelmValues: false
      serviceMonitorNamespaceSelector: {}
      
      # Resource requests/limits
      resources:
        requests:
          cpu: 1
          memory: 2Gi
        limits:
          cpu: 2
          memory: 4Gi
```

### Example 3: Restrict to Specific Namespaces
```yaml
kube-prometheus-stack:
  prometheusSpec:
    # Only monitor namespaces with label monitoring=enabled
    serviceMonitorNamespaceSelector:
      matchLabels:
        monitoring: enabled
    
    podMonitorNamespaceSelector:
      matchLabels:
        monitoring: enabled
```

---

## Troubleshooting

### Problem: Prometheus not discovering ServiceMonitors
**Solution:**
```yaml
# Check these settings:
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # Must be false
    serviceMonitorNamespaceSelector: {}              # Must be empty or have correct labels
```

### Problem: "No targets" in Prometheus UI
**Solution:**
1. Check ServiceMonitor labels match prometheus selectors
2. Verify exporter pods are running: `kubectl get pods -l app=mysql-exporter`
3. Check if exporters have correct port in ServiceMonitor

### Problem: High disk usage
**Solution:**
```yaml
prometheus:
  prometheusSpec:
    retention: 7d          # Reduce retention
    retentionSize: 20Gi    # Add size-based retention
```

---

## Production Checklist

- [ ] Change Grafana admin password from "admin"
- [ ] Enable persistent storage for Prometheus
- [ ] Set retention policy based on needs (15-30 days typical)
- [ ] Configure resource requests/limits
- [ ] Set up AlertManager rules
- [ ] Enable RBAC and network policies
- [ ] Use TLS for all ingress routes
- [ ] Monitor storage consumption
- [ ] Backup Prometheus data regularly
- [ ] Test alerting channels (Slack, PagerDuty, etc.)

---

## Reference

- [Kube-Prometheus-Stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Grafana Dashboard Library](https://grafana.com/grafana/dashboards/)
- [ServiceMonitor CRD](https://prometheus-operator.dev/docs/prometheus/latest/configuration/servicemonitor/)
