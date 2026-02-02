# External Charts Guide
## Adding Charts from Internet (Redis, Prometheus, Cert-Manager)

---

## Table of Contents

1. [What are External Charts](#what-are-external-charts)
2. [Popular Chart Repositories](#popular-chart-repositories)
3. [Adding External Charts to Umbrella Chart](#adding-external-charts-to-umbrella-chart)
4. [Where to Add External Chart Values](#where-to-add-external-chart-values)
5. [Complete Examples](#complete-examples)
6. [Commands and Workflow](#commands-and-workflow)

---

## What are External Charts

**External charts** = pre-built Helm charts from the internet (not your custom charts).

### Why Use External Charts?

| Build Your Own | Use External Chart |
|----------------|-------------------|
| ❌ 500+ lines of YAML | ✅ Configure with 20 lines |
| ❌ Maintain updates | ✅ Maintained by community |
| ❌ Debug issues | ✅ Battle-tested |
| ❌ Security patches | ✅ Regular updates |
| ⏱️ Days to build | ⏱️ Minutes to deploy |

### Common External Charts

- **Redis**: Bitnami Redis (caching)
- **RabbitMQ**: Bitnami RabbitMQ (message queue)
- **MongoDB**: Bitnami MongoDB (database)
- **MySQL**: Bitnami MySQL (database)
- **Prometheus**: Prometheus Community (monitoring)
- **Grafana**: Grafana Labs (dashboards)
- **Cert-Manager**: Jetstack (SSL certificates)
- **Ingress-NGINX**: Kubernetes (ingress controller)

---

## Popular Chart Repositories

### 1. Bitnami (Most Popular)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search for charts
helm search repo bitnami | grep redis
helm search repo bitnami | grep mysql
```

**Charts:**
- `bitnami/redis`
- `bitnami/mysql`
- `bitnami/mongodb`
- `bitnami/rabbitmq`
- `bitnami/postgresql`
- `bitnami/kafka`
- `bitnami/elasticsearch`

### 2. Prometheus Community

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm search repo prometheus-community
```

**Charts:**
- `prometheus-community/prometheus`
- `prometheus-community/kube-prometheus-stack` (Prometheus + Grafana + Alertmanager)

### 3. Jetstack (Cert-Manager)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm search repo jetstack
```

**Charts:**
- `jetstack/cert-manager` (Auto SSL certificates)

### 4. Ingress-NGINX

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm search repo ingress-nginx
```

**Charts:**
- `ingress-nginx/ingress-nginx` (Nginx ingress controller)

### 5. Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm search repo grafana
```

**Charts:**
- `grafana/grafana`
- `grafana/loki` (Log aggregation)

---

## Adding External Charts to Umbrella Chart

### Method 1: As Dependencies in Chart.yaml (Recommended)

This automatically downloads and manages external charts.

#### File: `robot-shop/Chart.yaml`

```yaml
apiVersion: v2
name: robot-shop
description: A complete microservices application
type: application
version: 1.0.0
appVersion: "2.1.0"

# External chart dependencies
dependencies:
  # Bitnami Redis
  - name: redis
    version: "18.x.x"                          # Version constraint
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled                    # Can be disabled
    alias: redis                                # Optional: rename
  
  # Bitnami RabbitMQ
  - name: rabbitmq
    version: "12.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: rabbitmq.enabled
  
  # Bitnami MongoDB
  - name: mongodb
    version: "14.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: mongodb.enabled
  
  # Bitnami MySQL
  - name: mysql
    version: "9.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: mysql.enabled
  
  # Prometheus Stack (Prometheus + Grafana)
  - name: kube-prometheus-stack
    version: "54.x.x"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: monitoring.enabled
    alias: monitoring
  
  # Cert-Manager (SSL certificates)
  - name: cert-manager
    version: "v1.13.x"
    repository: "https://charts.jetstack.io"
    condition: certManager.enabled
    alias: certManager
  
  # Ingress-NGINX
  - name: ingress-nginx
    version: "4.8.x"
    repository: "https://kubernetes.github.io/ingress-nginx"
    condition: ingressNginx.enabled
    alias: ingressNginx
```

#### Key Fields

- **name**: Chart name from repository
- **version**: Version constraint (`18.x.x` = any 18.x version)
- **repository**: Chart repository URL
- **condition**: Enable/disable via values (e.g., `redis.enabled: true`)
- **alias**: Rename chart in your values (optional)

---

### Method 2: Download and Include Manually

```bash
# Download chart
helm pull bitnami/redis --untar --untardir robot-shop/charts/

# Result: robot-shop/charts/redis/
```

**When to use:**
- Need specific version permanently
- Want to modify chart locally
- Working offline

---

## Where to Add External Chart Values

### Location: Umbrella Chart's values.yaml

External chart values go in the **umbrella chart's values.yaml**, under the chart name (or alias).

#### File: `robot-shop/values.yaml`

```yaml
# ============================================
# YOUR CUSTOM SERVICES
# ============================================

user:
  name: user
  tier: backend
  # ... your user service config

web:
  name: web
  tier: frontend
  # ... your web service config

# ============================================
# EXTERNAL CHARTS (from dependencies)
# ============================================

# Redis (Bitnami)
redis:
  enabled: true                    # Enable this dependency
  
  # Bitnami Redis specific values
  architecture: standalone         # or "replication"
  
  auth:
    enabled: true
    password: "Redis123!"          # ⚠️ Use secrets in production
  
  master:
    persistence:
      enabled: true
      size: 8Gi
      storageClass: "standard"
    
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
  
  metrics:
    enabled: true                  # Prometheus metrics

# RabbitMQ (Bitnami)
rabbitmq:
  enabled: true
  
  auth:
    username: admin
    password: "Rabbit123!"         # ⚠️ Use secrets in production
  
  persistence:
    enabled: true
    size: 8Gi
  
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
  
  metrics:
    enabled: true

# MongoDB (Bitnami) - only if not using your custom chart
mongodb:
  enabled: false                   # Disabled (using custom chart)

# MySQL (Bitnami) - only if not using your custom chart
mysql:
  enabled: false                   # Disabled (using custom chart)

# Prometheus Stack (Monitoring)
monitoring:
  enabled: true
  
  # Prometheus
  prometheus:
    enabled: true
    
    prometheusSpec:
      retention: 7d
      
      resources:
        requests:
          cpu: "500m"
          memory: "2Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      
      storageSpec:
        volumeClaimTemplate:
          spec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 50Gi
  
  # Grafana
  grafana:
    enabled: true
    
    adminPassword: "Admin123!"     # ⚠️ Use secrets in production
    
    persistence:
      enabled: true
      size: 10Gi
    
    ingress:
      enabled: true
      hosts:
        - grafana.robot-shop.com
  
  # Alertmanager
  alertmanager:
    enabled: true

# Cert-Manager (SSL Certificates)
certManager:
  enabled: true
  
  installCRDs: true                # Install Custom Resource Definitions
  
  resources:
    requests:
      cpu: "10m"
      memory: "32Mi"
    limits:
      cpu: "100m"
      memory: "128Mi"

# Ingress-NGINX Controller
ingressNginx:
  enabled: true
  
  controller:
    kind: DaemonSet              # Run on all nodes
    
    service:
      type: LoadBalancer         # Cloud load balancer
      
    metrics:
      enabled: true
      
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
```

---

## Complete Examples

### Example 1: Adding Redis (Bitnami)

#### Step 1: Add to Chart.yaml

```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: redis
    version: "18.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
```

#### Step 2: Add Values

```yaml
# robot-shop/values.yaml

redis:
  enabled: true
  
  # How you want Redis to run
  architecture: standalone    # Options: standalone, replication
  
  # Authentication
  auth:
    enabled: true
    password: "MyRedisPassword"
  
  # Master node configuration
  master:
    persistence:
      enabled: true
      size: 8Gi
      storageClass: "standard"
    
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
  
  # Metrics for Prometheus
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

#### Step 3: Update Dependencies

```bash
cd /home/abdelrahman/Desktop/DevOps/robot-shop/helm/robot-shop

# Download Redis chart
helm dependency update

# Verify
helm dependency list

# Result: Redis chart downloaded to robot-shop/charts/redis/
```

#### Step 4: Deploy

```bash
helm install robot-shop ./robot-shop -n robot-shop
```

---

### Example 2: Adding Prometheus + Grafana

#### Step 1: Add to Chart.yaml

```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: kube-prometheus-stack
    version: "54.x.x"
    repository: "https://prometheus-community.github.io/helm-charts"
    condition: monitoring.enabled
    alias: monitoring
```

#### Step 2: Add Values

```yaml
# robot-shop/values.yaml

monitoring:
  enabled: true
  
  # Prometheus configuration
  prometheus:
    enabled: true
    
    prometheusSpec:
      retention: 7d               # Keep metrics for 7 days
      
      # Resource limits
      resources:
        requests:
          cpu: "500m"
          memory: "2Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      
      # Storage
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: standard
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 50Gi
      
      # Service monitors (auto-discover metrics)
      serviceMonitorSelectorNilUsesHelmValues: false
  
  # Grafana configuration
  grafana:
    enabled: true
    
    # Admin credentials
    adminUser: admin
    adminPassword: "GrafanaAdmin123!"
    
    # Persistence
    persistence:
      enabled: true
      size: 10Gi
      storageClassName: standard
    
    # Ingress (external access)
    ingress:
      enabled: true
      ingressClassName: nginx
      hosts:
        - grafana.robot-shop.com
      tls:
        - secretName: grafana-tls
          hosts:
            - grafana.robot-shop.com
    
    # Pre-installed dashboards
    dashboardProviders:
      dashboardproviders.yaml:
        apiVersion: 1
        providers:
        - name: 'default'
          folder: 'General'
          type: file
          options:
            path: /var/lib/grafana/dashboards/default
  
  # Alertmanager configuration
  alertmanager:
    enabled: true
    
    alertmanagerSpec:
      retention: 120h
      
      storage:
        volumeClaimTemplate:
          spec:
            storageClassName: standard
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 10Gi
```

#### Step 3: Update and Deploy

```bash
helm dependency update robot-shop/
helm install robot-shop ./robot-shop -n robot-shop

# Access Grafana
kubectl port-forward -n robot-shop svc/monitoring-grafana 3000:80

# Visit: http://localhost:3000
# Login: admin / GrafanaAdmin123!
```

---

### Example 3: Adding Cert-Manager (Auto SSL)

#### Step 1: Add to Chart.yaml

```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: cert-manager
    version: "v1.13.x"
    repository: "https://charts.jetstack.io"
    condition: certManager.enabled
    alias: certManager
```

#### Step 2: Add Values

```yaml
# robot-shop/values.yaml

certManager:
  enabled: true
  
  # Install CRDs (required)
  installCRDs: true
  
  # Resource limits
  resources:
    requests:
      cpu: "10m"
      memory: "32Mi"
    limits:
      cpu: "100m"
      memory: "128Mi"
  
  # Webhook configuration
  webhook:
    resources:
      requests:
        cpu: "10m"
        memory: "32Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
  
  # CA Injector
  cainjector:
    resources:
      requests:
        cpu: "10m"
        memory: "32Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
```

#### Step 3: Create ClusterIssuer (After Installation)

```yaml
# cert-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

```bash
helm dependency update robot-shop/
helm install robot-shop ./robot-shop -n robot-shop

# Apply ClusterIssuer
kubectl apply -f cert-issuer.yaml
```

#### Step 4: Use in Ingress

```yaml
# robot-shop/values.yaml

web:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - robot-shop.com
    tls:
      - secretName: robot-shop-tls
        hosts:
          - robot-shop.com
```

---

## Commands and Workflow

### 1. Add Helm Repositories

```bash
# Add popular repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add grafana https://grafana.github.io/helm-charts

# Update repository index
helm repo update

# List all repos
helm repo list
```

### 2. Search for Charts

```bash
# Search all repos
helm search repo redis

# Search specific repo
helm search repo bitnami/redis

# Show all versions
helm search repo bitnami/redis --versions

# Show chart details
helm show chart bitnami/redis

# Show default values
helm show values bitnami/redis

# Show README
helm show readme bitnami/redis
```

### 3. Update Dependencies

```bash
cd /home/abdelrahman/Desktop/DevOps/robot-shop/helm/robot-shop

# Download dependencies (after adding to Chart.yaml)
helm dependency update

# List dependencies
helm dependency list

# Verify downloaded charts
ls charts/

# Result: charts/redis-18.x.x.tgz
```

### 4. Deploy with External Charts

```bash
# Install
helm install robot-shop ./robot-shop -n robot-shop --create-namespace

# Upgrade
helm upgrade robot-shop ./robot-shop -n robot-shop

# Uninstall
helm uninstall robot-shop -n robot-shop
```

### 5. Override External Chart Values

```bash
# Command line override
helm install robot-shop ./robot-shop -n robot-shop \
  --set redis.master.resources.requests.memory=256Mi \
  --set monitoring.prometheus.prometheusSpec.retention=14d

# Via values file
helm install robot-shop ./robot-shop -n robot-shop \
  -f values-prod.yaml
```

---

## Finding Required Values

### Method 1: Show Default Values

```bash
# See all available values for a chart
helm show values bitnami/redis

# Save to file for reference
helm show values bitnami/redis > redis-values.yaml

# Edit and use
vim redis-values.yaml
helm install redis bitnami/redis -f redis-values.yaml
```

### Method 2: Chart Documentation

```bash
# Show README
helm show readme bitnami/redis

# Or visit ArtifactHub
# https://artifacthub.io/packages/helm/bitnami/redis
```

### Method 3: Explore Chart Structure

```bash
# Pull chart locally
helm pull bitnami/redis --untar

# Explore
cd redis/
ls -la
cat README.md
cat values.yaml
cat templates/master/statefulset.yaml
```

---

## Environment-Specific External Chart Values

### values-dev.yaml

```yaml
redis:
  enabled: true
  master:
    persistence:
      size: 1Gi           # Small for dev
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"

monitoring:
  enabled: false          # Disabled in dev
```

### values-prod.yaml

```yaml
redis:
  enabled: true
  architecture: replication  # HA with replicas
  master:
    persistence:
      size: 50Gi             # Large for prod
      storageClass: fast-ssd
    resources:
      requests:
        cpu: "500m"
        memory: "2Gi"
      limits:
        cpu: "2000m"
        memory: "4Gi"
  replica:
    replicaCount: 3          # 3 replicas for HA

monitoring:
  enabled: true              # Enabled in prod
  prometheus:
    prometheusSpec:
      retention: 30d         # Keep 30 days of metrics
      resources:
        requests:
          memory: "8Gi"
```

---

## Troubleshooting

### Issue: Chart not found

```bash
# Error: chart "redis" not found in https://charts.bitnami.com/bitnami

# Fix: Update repo
helm repo update
helm search repo bitnami/redis

# If still not found, check repo URL
helm repo list
```

### Issue: Dependency download failed

```bash
# Error: failed to download "bitnami/redis"

# Fix: Update dependencies with verbose output
helm dependency update robot-shop/ --debug

# Manual download
helm pull bitnami/redis --version 18.1.0 --untar --untardir robot-shop/charts/
```

### Issue: Wrong values not being applied

```bash
# Check if external chart is enabled
helm get values robot-shop -n robot-shop | grep -A 10 "redis:"

# Check what values external chart uses
kubectl get statefulset -n robot-shop redis-master -o yaml
```

---

## Summary

### Key Takeaways

1. **Add to Chart.yaml** dependencies section
2. **Configure in values.yaml** under chart name
3. **Run `helm dependency update`** to download
4. **Use `helm show values`** to see available options
5. **Environment-specific** values in values-{env}.yaml
6. **Enable/disable** with `enabled: true/false`

### Common External Charts Commands

```bash
# Redis
helm repo add bitnami https://charts.bitnami.com/bitnami
helm show values bitnami/redis > redis-values.yaml

# Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm show values prometheus-community/kube-prometheus-stack > prometheus-values.yaml

# Cert-Manager
helm repo add jetstack https://charts.jetstack.io
helm show values jetstack/cert-manager > cert-manager-values.yaml

# Update all repos
helm repo update

# Download dependencies
helm dependency update robot-shop/

# Deploy
helm install robot-shop ./robot-shop -n robot-shop
```
