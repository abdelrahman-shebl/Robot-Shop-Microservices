# Values Discovery Guide
## How to Find Required Values from Any Helm Chart

---

## Table of Contents

1. [Why Values Discovery Matters](#why-values-discovery-matters)
2. [Methods to Discover Chart Values](#methods-to-discover-chart-values)
3. [Understanding values.yaml Structure](#understanding-valuesyaml-structure)
4. [Identifying Required vs Optional Values](#identifying-required-vs-optional-values)
5. [Complete Examples](#complete-examples)
6. [Advanced Discovery Techniques](#advanced-discovery-techniques)
7. [Tools and Commands](#tools-and-commands)

---

## Why Values Discovery Matters

When adding an external chart (Redis, Prometheus, Cert-Manager), you need to know:

1. **What values are available?** (all configuration options)
2. **Which values are required?** (must be set)
3. **What are the defaults?** (what happens if you don't change them)
4. **How to configure for your needs?** (dev vs prod)

Without values discovery, you're **flying blind** 🛫❌

---

## Methods to Discover Chart Values

### Method 1: helm show values (Recommended)

**The fastest way** to see all available values.

```bash
# Show values for a chart
helm show values bitnami/redis

# Save to file for easier reading
helm show values bitnami/redis > redis-values.yaml

# View in editor
vim redis-values.yaml
```

#### Example Output

```yaml
## @section Global parameters
## @param global.imageRegistry Global Docker image registry
## @param global.imagePullSecrets Global Docker registry secret names

global:
  imageRegistry: ""
  imagePullSecrets: []
  storageClass: ""

## @section Common parameters

## @param nameOverride String to partially override common.names.name
nameOverride: ""

## @param fullnameOverride String to fully override common.names.fullname
fullnameOverride: ""

## @param architecture Redis architecture (standalone or replication)
architecture: standalone

## @param auth.enabled Enable password authentication
auth:
  enabled: true
  password: ""
  
## @param master.persistence.enabled Enable persistence on Redis master
master:
  persistence:
    enabled: true
    size: 8Gi
    storageClass: ""
```

**Key Insight:** Each `@param` comment describes what the value does.

---

### Method 2: helm show readme

**Best for understanding the big picture.**

```bash
# Show chart README
helm show readme bitnami/redis

# Save to file
helm show readme bitnami/redis > redis-README.md
```

#### What You'll Find

- **Chart description** (what the chart does)
- **Prerequisites** (what you need installed)
- **Installation instructions**
- **Configuration** (table of important values)
- **Examples** (common use cases)
- **Troubleshooting**

---

### Method 3: ArtifactHub.io (Web UI)

**Most user-friendly** for browsing.

1. Visit: https://artifacthub.io
2. Search for chart (e.g., "redis")
3. Click on the chart
4. View:
   - Default values (with descriptions)
   - README
   - Templates
   - Available versions

**Screenshot workflow:**
```
artifacthub.io → Search "redis" → Click "bitnami/redis" → Tab "Default Values"
```

---

### Method 4: Pull Chart and Explore

**Deep dive** into how the chart works.

```bash
# Pull chart locally
helm pull bitnami/redis --untar

# Explore structure
cd redis/
ls -la

# Files:
# - Chart.yaml       (metadata)
# - values.yaml      (all default values)
# - templates/       (Kubernetes YAML templates)
# - README.md        (documentation)
```

#### Why Pull?

- See **exactly** how values are used in templates
- Understand **template logic**
- Find **hidden features** not documented

---

### Method 5: helm show chart

**Metadata about the chart.**

```bash
helm show chart bitnami/redis
```

#### Example Output

```yaml
apiVersion: v2
name: redis
version: 18.1.0
appVersion: 7.2.3
description: Redis is an open source, advanced key-value store.
keywords:
  - redis
  - keyvalue
  - database
home: https://bitnami.com
sources:
  - https://github.com/bitnami/charts/tree/main/bitnami/redis
maintainers:
  - name: Bitnami
    email: containers@bitnami.com
```

---

## Understanding values.yaml Structure

### Anatomy of values.yaml

```yaml
# ============================================
# SECTION 1: GLOBAL PARAMETERS
# ============================================

## @section Global parameters
## @param global.imageRegistry Global Docker image registry

global:
  imageRegistry: ""               # ← Empty string = use default
  storageClass: ""                # ← Empty string = use cluster default

# ============================================
# SECTION 2: COMMON PARAMETERS
# ============================================

## @param nameOverride Override chart name
nameOverride: ""                  # ← Optional

## @param architecture Redis architecture
## @values standalone, replication
architecture: standalone          # ← DEFAULT VALUE (standalone)

# ============================================
# SECTION 3: AUTHENTICATION
# ============================================

## @param auth.enabled Enable password authentication
auth:
  enabled: true                   # ← Boolean: true or false
  password: ""                    # ← Empty = auto-generate

# ============================================
# SECTION 4: MASTER NODE CONFIGURATION
# ============================================

master:
  ## @param master.count Number of Redis master instances
  count: 1                        # ← Number
  
  ## @param master.persistence.enabled Enable persistence
  persistence:
    enabled: true                 # ← Enabled by default
    size: 8Gi                     # ← Default size
    storageClass: ""              # ← Empty = cluster default
  
  ## @param master.resources Resource requests/limits
  resources:
    limits: {}                    # ← Empty = no limits
    requests: {}                  # ← Empty = no requests

# ============================================
# SECTION 5: REPLICA NODE CONFIGURATION
# ============================================

replica:
  replicaCount: 3                 # ← Number of replicas
  
  persistence:
    enabled: true
    size: 8Gi

# ============================================
# SECTION 6: METRICS (PROMETHEUS)
# ============================================

metrics:
  enabled: false                  # ← Disabled by default
  
  serviceMonitor:
    enabled: false                # ← Requires Prometheus Operator
```

### Value Types

| Type | Example | Meaning |
|------|---------|---------|
| Empty string `""` | `storageClass: ""` | Use system default |
| String | `architecture: standalone` | Specific value |
| Boolean | `enabled: true` | Yes/no flag |
| Number | `replicaCount: 3` | Numeric value |
| Empty map `{}` | `resources: {}` | No value set |
| List | `- value1\n- value2` | Array of values |

---

## Identifying Required vs Optional Values

### How to Tell What's Required

#### 1. Look for Comments

```yaml
## REQUIRED: You must set this value
password: ""

## Optional: Leave empty to use default
storageClass: ""
```

#### 2. Look for Empty Values

```yaml
# Empty string = you should probably set this
auth:
  password: ""              # ← Set this in production

# Empty map = optional (chart will work without it)
resources: {}               # ← Optional: add if you want limits
```

#### 3. Read the README

```markdown
## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PV provisioner (for persistence)

## Required Values

- `auth.password` - Redis password (auto-generated if empty)
- `master.persistence.storageClass` - Storage class for PVCs
```

#### 4. Try helm lint

```bash
# Chart will fail validation if required values are missing
helm lint ./chart-name

# Or try a dry-run install
helm install test ./chart-name --dry-run --debug
```

---

### Common Required Values by Chart Type

#### Redis (Bitnami)

```yaml
# Usually required for production
redis:
  auth:
    password: "YourPassword"           # Required if auth.enabled=true
  
  master:
    persistence:
      storageClass: "standard"          # Required if no default StorageClass
```

#### MySQL (Bitnami)

```yaml
mysql:
  auth:
    rootPassword: "RootPassword"        # REQUIRED
    database: "mydb"                    # Required if creating DB
    username: "user"                    # Required if creating user
    password: "UserPassword"            # Required if creating user
  
  primary:
    persistence:
      storageClass: "standard"          # Required if no default
```

#### PostgreSQL (Bitnami)

```yaml
postgresql:
  auth:
    postgresPassword: "AdminPassword"   # REQUIRED
    username: "user"                    # Required for user
    password: "UserPassword"            # Required for user
    database: "mydb"                    # Required for DB
```

#### MongoDB (Bitnami)

```yaml
mongodb:
  auth:
    rootPassword: "RootPassword"        # REQUIRED
    username: "user"                    # Optional
    password: "UserPassword"            # Required if username set
    database: "mydb"                    # Optional
```

#### Prometheus (Community)

```yaml
prometheus:
  # Usually no required values!
  # Works out-of-the-box
  
  # But you probably want:
  prometheusSpec:
    retention: 7d                       # How long to keep metrics
    storageSpec:                        # Required for persistence
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 50Gi
```

#### Cert-Manager (Jetstack)

```yaml
certManager:
  installCRDs: true                     # REQUIRED (unless CRDs exist)
  
  # After install, you need ClusterIssuer (separate YAML)
```

---

## Complete Examples

### Example 1: Discovering Redis Values

#### Step 1: Show All Values

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Show values (3000+ lines!)
helm show values bitnami/redis | less

# Save to file
helm show values bitnami/redis > redis-all-values.yaml
```

#### Step 2: Identify Important Sections

Open `redis-all-values.yaml` and scan for:

```yaml
# ====================
# CRITICAL SECTIONS
# ====================

## Architecture: standalone vs replication (HA)
architecture: standalone

## Authentication
auth:
  enabled: true
  password: ""                 # ⚠️ SET THIS

## Master node
master:
  persistence:
    enabled: true
    size: 8Gi
    storageClass: ""           # ⚠️ CHECK THIS
  
  resources:
    limits: {}                 # ⚠️ SET FOR PRODUCTION
    requests: {}

## Replica nodes (if architecture: replication)
replica:
  replicaCount: 3
  persistence:
    enabled: true
    size: 8Gi

## Metrics (Prometheus)
metrics:
  enabled: false               # ⚠️ ENABLE FOR MONITORING
```

#### Step 3: Create Minimal Configuration

```yaml
# robot-shop/values.yaml

redis:
  enabled: true
  
  # Architecture
  architecture: standalone     # Change to 'replication' for HA
  
  # Authentication
  auth:
    enabled: true
    password: "Redis123!"      # ⚠️ Change this
  
  # Master configuration
  master:
    persistence:
      enabled: true
      size: 8Gi
      storageClass: "standard" # Your cluster's StorageClass
    
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
  
  # Metrics
  metrics:
    enabled: true
```

#### Step 4: Validate

```bash
helm dependency update robot-shop/
helm install robot-shop ./robot-shop -n robot-shop --dry-run --debug | less

# Check for errors
```

---

### Example 2: Discovering Prometheus Stack Values

#### Step 1: Show Values

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# WARNING: This chart has 5000+ lines of values!
helm show values prometheus-community/kube-prometheus-stack > prometheus-all-values.yaml
```

#### Step 2: Read README First

```bash
helm show readme prometheus-community/kube-prometheus-stack | less
```

**Key sections from README:**

- **What's included**: Prometheus, Grafana, Alertmanager, Node Exporter, Kube State Metrics
- **Default behavior**: Works out-of-box, creates ServiceMonitors automatically
- **Common configs**: Storage, ingress, Grafana admin password

#### Step 3: Find Critical Values

```yaml
# Search for keywords in values file
grep -n "adminPassword" prometheus-all-values.yaml
grep -n "storageSpec" prometheus-all-values.yaml
grep -n "ingress:" prometheus-all-values.yaml
```

#### Step 4: Create Configuration

```yaml
# robot-shop/values.yaml

monitoring:
  enabled: true
  
  # Prometheus
  prometheus:
    enabled: true
    
    prometheusSpec:
      retention: 7d            # How long to keep metrics
      
      resources:
        requests:
          cpu: "500m"
          memory: "2Gi"
        limits:
          cpu: "2000m"
          memory: "4Gi"
      
      # Persistent storage
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: standard
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 50Gi
  
  # Grafana
  grafana:
    enabled: true
    
    # Admin credentials (REQUIRED to login)
    adminPassword: "Admin123!"
    
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
  
  # Alertmanager
  alertmanager:
    enabled: true
```

---

### Example 3: Discovering Cert-Manager Values

#### Step 1: Show Values

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm show values jetstack/cert-manager > cert-manager-values.yaml
```

#### Step 2: Check README

```bash
helm show readme jetstack/cert-manager | less
```

**Critical info from README:**

> **IMPORTANT**: You MUST set `installCRDs: true` or install CRDs manually

#### Step 3: Minimal Configuration

```yaml
# robot-shop/values.yaml

certManager:
  enabled: true
  
  # REQUIRED: Install Custom Resource Definitions
  installCRDs: true
  
  # Optional: Resource limits
  resources:
    requests:
      cpu: "10m"
      memory: "32Mi"
    limits:
      cpu: "100m"
      memory: "128Mi"
```

#### Step 4: Post-Install Configuration

Cert-Manager requires a **ClusterIssuer** (separate from chart):

```yaml
# cert-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@robot-shop.com        # ⚠️ REQUIRED
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

```bash
kubectl apply -f cert-issuer.yaml
```

---

## Advanced Discovery Techniques

### Technique 1: Search for Keywords

```bash
# Find all authentication-related values
helm show values bitnami/redis | grep -i "auth" -A 5

# Find all persistence values
helm show values bitnami/redis | grep -i "persistence" -A 10

# Find resource limits
helm show values bitnami/redis | grep -i "resources" -A 5

# Find ingress config
helm show values bitnami/redis | grep -i "ingress" -A 10
```

### Technique 2: Compare Multiple Charts

```bash
# See how different charts handle similar concepts
helm show values bitnami/redis | grep -A 10 "persistence"
helm show values bitnami/mysql | grep -A 10 "persistence"
helm show values bitnami/mongodb | grep -A 10 "persistence"

# Pattern: They all use similar structure!
```

### Technique 3: Read Template Files

```bash
# Pull chart
helm pull bitnami/redis --untar
cd redis/templates/

# See how values are used
cat master/statefulset.yaml | grep -i "password"

# Result: Shows you where password value is used
{{- if .Values.auth.enabled }}
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "redis.secretName" . }}
        key: redis-password
{{- end }}
```

### Technique 4: Use helm template to Test

```bash
# Render templates with your values
helm template test bitnami/redis \
  --set auth.password=TestPass \
  --set master.persistence.size=20Gi

# Output shows final YAML with your values applied
```

---

## Tools and Commands

### Essential Commands

```bash
# 1. Show all values
helm show values <repo>/<chart>

# 2. Show README
helm show readme <repo>/<chart>

# 3. Show chart metadata
helm show chart <repo>/<chart>

# 4. Show everything
helm show all <repo>/<chart>

# 5. Search for chart
helm search repo <keyword>

# 6. List available versions
helm search repo <repo>/<chart> --versions

# 7. Pull chart locally
helm pull <repo>/<chart> --untar

# 8. Test your values
helm template <release-name> <repo>/<chart> -f your-values.yaml

# 9. Dry-run install
helm install <release-name> <repo>/<chart> -f your-values.yaml --dry-run --debug
```

### Workflow: Discovering Values for New Chart

```bash
#!/bin/bash
CHART="bitnami/redis"
NAME="redis"

# Step 1: Show everything
helm show all $CHART > ${NAME}-full.txt

# Step 2: Extract sections
helm show values $CHART > ${NAME}-values.yaml
helm show readme $CHART > ${NAME}-README.md
helm show chart $CHART > ${NAME}-Chart.yaml

# Step 3: Pull for deep dive
helm pull $CHART --untar

# Step 4: Read documentation
cat ${NAME}-README.md | less

# Step 5: Identify important values
grep -i "required" ${NAME}-README.md
grep -i "must" ${NAME}-README.md

# Step 6: Create your values
vim my-${NAME}-values.yaml

# Step 7: Test
helm template test $CHART -f my-${NAME}-values.yaml | less

# Step 8: Validate
helm lint $NAME/

# Step 9: Deploy
helm install $NAME $CHART -f my-${NAME}-values.yaml
```

---

## Quick Reference Tables

### Common Value Patterns Across Charts

| Value | Purpose | Usually Required? |
|-------|---------|-------------------|
| `auth.password` | Authentication | Yes (databases) |
| `persistence.size` | Storage size | No (has default) |
| `persistence.storageClass` | Storage class | Sometimes |
| `resources.requests` | Min resources | No (but recommended) |
| `resources.limits` | Max resources | No (but recommended) |
| `ingress.enabled` | External access | No |
| `ingress.hosts` | Hostnames | Yes if ingress enabled |
| `metrics.enabled` | Prometheus metrics | No |
| `replicaCount` | Number of pods | No (has default) |

### Values Discovery Checklist

- [ ] Run `helm show values <chart>`
- [ ] Run `helm show readme <chart>`
- [ ] Check ArtifactHub.io for examples
- [ ] Identify authentication values
- [ ] Identify persistence values
- [ ] Identify resource limit values
- [ ] Identify ingress values (if needed)
- [ ] Check for required CRDs or dependencies
- [ ] Test with `--dry-run --debug`
- [ ] Validate with `helm lint`

---

## Real-World Example: Adding Unknown Chart

Let's say you want to add **Loki** (log aggregation) but know nothing about it.

### Step 1: Find the Chart

```bash
helm search hub loki

# Result: grafana/loki
```

### Step 2: Add Repository

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Step 3: Gather Information

```bash
# README
helm show readme grafana/loki | less

# Key findings:
# - Loki is a log aggregation system
# - Has multiple components: gateway, distributor, ingester
# - Requires persistent storage
# - Integrates with Grafana
```

### Step 4: View Values

```bash
helm show values grafana/loki > loki-values.yaml
vim loki-values.yaml

# Scan for critical sections...
```

### Step 5: Identify Key Values

```yaml
# From loki-values.yaml

# Deployment mode: SingleBinary (simple) or SimpleScalable (prod)
deploymentMode: SingleBinary

# Storage
singleBinary:
  persistence:
    enabled: false          # ⚠️ Enable for production
    size: 10Gi

# Resources
resources:
  limits: {}
  requests: {}

# Gateway (ingress)
gateway:
  enabled: true
  
  ingress:
    enabled: false          # ⚠️ Enable for external access
```

### Step 6: Create Your Configuration

```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: loki
    version: "5.x.x"
    repository: "https://grafana.github.io/helm-charts"
    condition: loki.enabled
    alias: loki

# robot-shop/values.yaml
loki:
  enabled: true
  
  # Use simple single binary mode
  deploymentMode: SingleBinary
  
  # Enable persistence
  singleBinary:
    persistence:
      enabled: true
      size: 20Gi
      storageClass: standard
    
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
  
  # Enable ingress
  gateway:
    enabled: true
    
    ingress:
      enabled: true
      ingressClassName: nginx
      hosts:
        - host: loki.robot-shop.com
          paths:
            - path: /
              pathType: Prefix
```

### Step 7: Deploy and Test

```bash
helm dependency update robot-shop/
helm install robot-shop ./robot-shop -n robot-shop

# Check Loki pods
kubectl get pods -n robot-shop | grep loki

# Access Loki
kubectl port-forward -n robot-shop svc/loki-gateway 3100:80

# Test query
curl http://localhost:3100/loki/api/v1/labels
```

---

## Summary

### The 3-Step Process

1. **Gather Information**
   ```bash
   helm show values <chart>
   helm show readme <chart>
   ```

2. **Identify Critical Values**
   - Authentication (passwords)
   - Persistence (storage)
   - Resources (limits)
   - Ingress (external access)

3. **Start Minimal, Iterate**
   ```yaml
   chart:
     enabled: true
     # Add only what you need
     # Use defaults for the rest
   ```

### Commands to Remember

```bash
# Essential discovery commands
helm show values <repo>/<chart>      # All configuration options
helm show readme <repo>/<chart>      # Documentation
helm pull <repo>/<chart> --untar     # Download for deep dive

# Testing commands
helm template <name> <chart> -f values.yaml --debug
helm install <name> <chart> -f values.yaml --dry-run --debug
helm lint <chart-directory>

# Finding charts
helm search repo <keyword>           # Search added repos
helm search hub <keyword>            # Search Artifact Hub
```

### Best Practices

1. **Always read the README first** - saves time
2. **Start with minimal values** - add complexity as needed
3. **Use `--dry-run --debug`** - catch errors before deploying
4. **Save default values** - reference for future changes
5. **Check ArtifactHub.io** - community examples and tips
6. **Test in dev first** - never YOLO in production

### When in Doubt

```bash
# This combination tells you everything
helm show all <repo>/<chart> > chart-complete.txt
cat chart-complete.txt | less
```

Happy value hunting! 🔍📊
