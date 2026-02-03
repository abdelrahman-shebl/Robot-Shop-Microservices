# Multi-Environment Values Guide
## Managing Dev, Staging, and Production Configurations

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Values Hierarchy](#values-hierarchy)
3. [Creating Environment-Specific Values](#creating-environment-specific-values)
4. [Partial Overrides (Modify Only Certain Values)](#partial-overrides)
5. [YAML Anchors & Aliases (DRY Principle)](#yaml-anchors--aliases-dry-principle)
6. [Complete Examples](#complete-examples)
7. [Commands and Workflow](#commands-and-workflow)
8. [Best Practices](#best-practices)

---

## The Problem

Different environments need different configurations:

| Configuration | Dev | Staging | Production |
|--------------|-----|---------|------------|
| Replicas | 1 | 2 | 5 |
| Resources | Small | Medium | Large |
| Log Level | debug | info | warn |
| External URLs | localhost | staging.com | example.com |
| HPA Max | 2 | 5 | 20 |
| Storage | 1Gi | 5Gi | 100Gi |

**Challenge**: How to maintain ONE chart with MULTIPLE environments?

---

## Values Hierarchy

Helm merges values in this order (last wins):

```
1. Chart's values.yaml (defaults)
   ↓
2. Parent chart's values (umbrella chart)
   ↓
3. Additional values files (-f values-prod.yaml)
   ↓
4. Individual --set flags
```

### Example

```bash
# 1. Default: chart/values.yaml
replicas: 1

# 2. Umbrella: robot-shop/values.yaml
replicas: 2

# 3. Environment file: values-prod.yaml
replicas: 5

# 4. Command line
--set replicas=10

# Final value: 10 (command line wins)
```

---

## Creating Environment-Specific Values

### Directory Structure

```
helm/
├── robot-shop/
│   ├── Chart.yaml
│   ├── values.yaml              ← Base/common values
│   └── charts/
│       ├── user/
│       ├── web/
│       └── ...
│
├── values-dev.yaml              ← Dev-specific overrides
├── values-staging.yaml          ← Staging-specific overrides
└── values-prod.yaml             ← Production-specific overrides
```

---

## Partial Overrides (Modify Only Certain Values)

### The Power of Helm Merging

You **DON'T** need to copy entire values.yaml!  
Helm **deep merges** values, so you only specify what changes.

### Example: Base values.yaml

```yaml
# robot-shop/values.yaml (BASE/DEFAULT)

user:
  name: user
  tier: backend
  replicas: 1                    # Default for all environments
  
  image:
    repository: robotshop
    name: user
    version: 2.1.0
  
  port: 8080
  
  env:
    MONGO_HOST: mongodb
    LOG_LEVEL: info              # Default log level
  
  resources:
    requests:
      cpu: "50m"                 # Small default
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  
  hpa:
    minReplicas: 1
    maxReplicas: 3               # Conservative default
    targetCPU: 70
  
  service:
    port: 8080

web:
  name: web
  tier: frontend
  replicas: 1
  
  image:
    repository: robotshop
    name: rs-web
    version: 2.1.0
  
  ingress:
    host: localhost              # Default for local dev
```

---

### Development Values (values-dev.yaml)

**Only override what's different for dev:**

```yaml
# values-dev.yaml
# Override ONLY development-specific values

user:
  replicas: 1                    # Keep default (could omit this)
  
  env:
    LOG_LEVEL: debug             # ← More logging for dev
  
  resources:
    requests:
      cpu: "50m"                 # Small for local dev
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  
  hpa:
    minReplicas: 1
    maxReplicas: 2               # ← Don't need many in dev

web:
  replicas: 1
  
  ingress:
    host: localhost              # ← Local development
  
  hpa:
    minReplicas: 1
    maxReplicas: 2

# Override other services similarly
ratings:
  replicas: 1
  env:
    LOG_LEVEL: debug
  hpa:
    maxReplicas: 2

mysql:
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        resources:
          requests:
            storage: 1Gi         # ← Small storage for dev
```

**Result**: Helm merges these with base values. Only `LOG_LEVEL`, `maxReplicas`, `storage`, and `host` change. Everything else stays from base values.yaml.

---

## YAML Anchors & Aliases (DRY Principle)

### The Problem: Code Duplication in Values Files

When managing multiple services with similar configurations, you end up repeating the same values across many services:

```yaml
# ❌ BAD: Lots of repetition
user:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2

web:
  resources:
    requests:
      cpu: "50m"        # ← Duplicate!
      memory: "64Mi"    # ← Duplicate!
    limits:
      cpu: "200m"       # ← Duplicate!
      memory: "128Mi"   # ← Duplicate!
  hpa:
    minReplicas: 1      # ← Duplicate!
    maxReplicas: 2      # ← Duplicate!

cart:
  resources:
    requests:
      cpu: "50m"        # ← Duplicate again!
      memory: "64Mi"    # ← Duplicate again!
    limits:
      cpu: "200m"       # ← Duplicate again!
      memory: "128Mi"   # ← Duplicate again!
  hpa:
    minReplicas: 1      # ← Duplicate again!
    maxReplicas: 2      # ← Duplicate again!
```

**Problems**:
- **Maintenance nightmare**: Change one value, need to update 5+ places
- **Error-prone**: Easy to miss a spot and introduce inconsistencies
- **Bloated files**: values-prod.yaml becomes unreadable

### The Solution: YAML Anchors (`&`) and Aliases (`<<:`)

YAML anchors allow you to define a value once and reuse it multiple times, following the **DRY** (Don't Repeat Yourself) principle.

#### What Are Anchors and Aliases?

- **Anchor (`&`)**: Marks a value with a label you can reuse
- **Alias (`*`)**: References the anchored value by name
- **Merge Key (`<<:`)**: Special YAML feature to merge anchored content into the current object

### Basic Syntax

```yaml
# 1. Define an anchor with &anchor_name
my_config: &my_config
  key1: value1
  key2: value2

# 2. Use an alias with *anchor_name OR merge with <<:
service1:
  <<: *my_config        # ← Merges all keys from my_config
  key3: value3          # ← Can add additional keys

service2:
  <<: *my_config        # ← Reuses the same config
```

**Result after YAML parsing**:
```yaml
service1:
  key1: value1
  key2: value2
  key3: value3

service2:
  key1: value1
  key2: value2
```

### Real Example: Development Values

#### The Robot Shop values-dev.yaml Pattern

```yaml
# Step 1: Define an anchor for common dev API values
default_dev_apis_values: &dev_apis_values
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2

# Step 2: Define another anchor for storage
storage_spec: &storage_spec
  accessModes: [ "ReadWriteOnce" ]
  resources:
    requests:
      storage: 200Mi

# Step 3: Reuse anchors with the merge key (<<:)
user:
  <<: *dev_apis_values          # ← Includes all dev_apis_values

web:
  <<: *dev_apis_values          # ← Reuses the same config
  ingress:
    host: shebl.com             # ← Additional custom values

cart:
  <<: *dev_apis_values          # ← Reuses again

shipping:
  <<: *dev_apis_values          # ← And again!

ratings:
  <<: *dev_apis_values

payment:
  <<: *dev_apis_values

dispatch:
  <<: *dev_apis_values

catalogue:
  <<: *dev_apis_values

# Database services use the storage anchor
mysql:
  replicas: 1
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      <<: *storage_spec         # ← Reuse storage config

mongodb:
  replicas: 1
  volumeClaimTemplates:
  - metadata:
      name: mongo-data
    spec:
      <<: *storage_spec         # ← Reuse again
```

#### What It Expands To

After YAML parsing, the above becomes:

```yaml
user:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2

web:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2
  ingress:
    host: shebl.com

cart:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2
```

**You write 40% less code, but get 100% of the values!**

### Advanced Patterns

#### Pattern 1: Nested Anchors

```yaml
# Define multiple levels
standard_resources: &standard_resources
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

standard_hpa: &standard_hpa
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 70

standard_service_config: &standard_service_config
  replicas: 2
  resources:
    <<: *standard_resources   # ← Nested anchor reference
  hpa:
    <<: *standard_hpa         # ← Nested anchor reference

# Use the composite anchor
user:
  <<: *standard_service_config

web:
  <<: *standard_service_config
  ingress:
    host: staging.example.com
```

#### Pattern 2: Multiple Anchors on One Service

```yaml
dev_resources: &dev_resources
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"

dev_hpa: &dev_hpa
  minReplicas: 1
  maxReplicas: 2

# Apply multiple anchors
user:
  replicas: 1
  resources:
    <<: *dev_resources
  hpa:
    <<: *dev_hpa
  env:
    LOG_LEVEL: debug           # ← Service-specific values
```

#### Pattern 3: Override Anchored Values

```yaml
default_config: &default_config
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"

# Merge anchor, then override specific values
payment:
  <<: *default_config
  resources:                   # ← Override the entire resources section
    requests:
      cpu: "200m"              # ← Higher for payment service
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
```

### Best Practices for Anchors & Aliases

#### 1. **Use Descriptive Anchor Names**

```yaml
# ✅ GOOD: Clear what this anchor is for
dev_api_service_defaults: &dev_api_service_defaults
  resources:
    requests:
      cpu: "50m"

# ❌ BAD: Unclear purpose
defaults: &d
  resources:
    requests:
      cpu: "50m"
```

#### 2. **Group Anchors at the Top**

```yaml
# ✅ GOOD: All anchors together
dev_api_resources: &dev_api_resources
  resources:
    requests:
      cpu: "50m"

dev_hpa: &dev_hpa
  minReplicas: 1
  maxReplicas: 2

# Services below use them
user:
  <<: *dev_api_resources
  <<: *dev_hpa
```

#### 3. **Use Anchors Across Environment Files**

Define in base values.yaml, reuse in all environment files:

```yaml
# robot-shop/values.yaml (BASE)
dev_resources: &dev_resources
  requests:
    cpu: "50m"
    memory: "64Mi"

prod_resources: &prod_resources
  requests:
    cpu: "500m"
    memory: "1Gi"

user:
  <<: *dev_resources  # Default for dev

# values-prod.yaml
user:
  <<: *prod_resources # Override with prod resources
```

#### 4. **Document Your Anchors**

```yaml
# YAML Anchors defined in this file:
# - &dev_api_resources: Standard resource requests/limits for dev API services
# - &storage_spec: Standard storage configuration for databases
# - &dev_hpa: Standard HPA settings for dev

dev_api_resources: &dev_api_resources
  resources:
    requests:
      cpu: "50m"
    # ... more values
```

#### 5. **Avoid Over-Nesting**

```yaml
# ✅ GOOD: Simple, readable
base_config: &base_config
  resources:
    requests:
      cpu: "50m"

service:
  <<: *base_config

# ❌ BAD: Too many levels
complex_anchor: &complex_anchor
  nested:
    deeply:
      buried:
        value: "hard to find"
```

### Common Mistakes

#### Mistake 1: Forgetting the Merge Key

```yaml
# ❌ WRONG: Alias alone doesn't merge
user: *dev_config

# ✅ CORRECT: Use merge key to merge keys
user:
  <<: *dev_config
```

#### Mistake 2: Overriding Anchor Values

```yaml
# The anchor itself is NOT changed by overrides
dev_config: &dev_config
  cpu: "50m"
  memory: "64Mi"

service1:
  <<: *dev_config
  cpu: "100m"  # ← This overrides the anchor value for this service only

service2:
  <<: *dev_config  # ← Still gets original "50m", not "100m"
```

#### Mistake 3: Mixing Anchor and YAML Comments

```yaml
# ❌ Be careful with comments on anchors
resources: &resources  # This is the anchor ← Comment here
  cpu: "50m"

# ✅ Better: Comment above the anchor
# Standard resource configuration for all services
resources: &resources
  cpu: "50m"
```

### Anchor Scope and Reusability

#### Within Same File

```yaml
# values-dev.yaml

dev_defaults: &dev_defaults
  cpu: "50m"

user:
  <<: *dev_defaults  # ✅ Works: same file

web:
  <<: *dev_defaults  # ✅ Works: same file
```

#### Across Files

```bash
# File 1: values-base.yaml
shared_config: &shared_config
  resources:
    cpu: "50m"

# File 2: values-prod.yaml
user:
  <<: *shared_config  # ❌ WON'T WORK: different files!
```

**Important**: Anchors are file-scoped. Define them in the same file where they're used, or repeat the anchor definition across files.

### When to Use Anchors

#### ✅ Use Anchors When:
- Multiple services need identical resource configs
- You want to reduce file duplication
- Values are used 3+ times in a file
- You want a single source of truth for default values

#### ❌ Don't Use Anchors When:
- Values are only used once or twice
- The anchor becomes harder to understand than the repetition
- Across different files (use Helm values hierarchy instead)

### Summary: Anchors vs Helm Values Merging

| Feature | YAML Anchors | Helm Values Merge |
|---------|--------------|-------------------|
| **Scope** | Within single file | Across multiple files |
| **Use Case** | Reduce duplication within a file | Layered environment configs |
| **Syntax** | `&name` and `<<: *name` | `-f values-prod.yaml` |
| **Merge Type** | Shallow merge | Deep merge |
| **Best For** | Repetitive values in one file | Different configs per environment |

### Real-World Comparison

#### Before Anchors (Robot Shop - verbose)
```yaml
user:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"

web:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"

cart:
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
# Repeat for shipping, ratings, payment, dispatch, catalogue...
```
**File size**: ~300 lines**

#### After Anchors (current robot-shop approach)
```yaml
default_dev_apis_values: &dev_apis_values
  resources:
    requests:
      cpu: "50m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
  hpa:
    minReplicas: 1
    maxReplicas: 2

user:
  <<: *dev_apis_values

web:
  <<: *dev_apis_values

cart:
  <<: *dev_apis_values

shipping:
  <<: *dev_apis_values

ratings:
  <<: *dev_apis_values

payment:
  <<: *dev_apis_values

dispatch:
  <<: *dev_apis_values

catalogue:
  <<: *dev_apis_values
```
**File size**: ~60 lines (80% reduction!)

---

### Staging Values (values-staging.yaml)

```yaml
# values-staging.yaml
# Override ONLY staging-specific values

user:
  replicas: 2                    # ← More than dev
  
  env:
    LOG_LEVEL: info              # ← Standard logging
  
  resources:
    requests:
      cpu: "100m"                # ← Medium resources
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
  
  hpa:
    minReplicas: 2
    maxReplicas: 5               # ← More scaling

web:
  replicas: 2
  
  ingress:
    host: staging.robot-shop.com # ← Staging domain
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-staging
  
  hpa:
    minReplicas: 2
    maxReplicas: 8

ratings:
  replicas: 2
  env:
    LOG_LEVEL: info
  hpa:
    maxReplicas: 5

mysql:
  replicas: 1
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        resources:
          requests:
            storage: 10Gi        # ← Medium storage

mongodb:
  replicas: 1
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        resources:
          requests:
            storage: 10Gi
```

---

### Production Values (values-prod.yaml)

```yaml
# values-prod.yaml
# Override ONLY production-specific values

# Global production settings
global:
  imagePullPolicy: IfNotPresent
  
  # Production security
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 3000

user:
  replicas: 5                    # ← High availability
  
  env:
    LOG_LEVEL: warn              # ← Less logging in prod
    MONITORING_ENABLED: "true"
  
  resources:
    requests:
      cpu: "200m"                # ← Large resources
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
  
  hpa:
    minReplicas: 5
    maxReplicas: 20              # ← Aggressive scaling
    targetCPU: 60                # ← Scale earlier
    targetMemory: 70
  
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 60      # ← Longer startup time
    periodSeconds: 10
    failureThreshold: 5
  
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 5
    failureThreshold: 3

web:
  replicas: 5
  
  ingress:
    host: robot-shop.com         # ← Production domain
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/rate-limit: "100"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls:
      - secretName: robot-shop-tls
        hosts:
          - robot-shop.com
  
  hpa:
    minReplicas: 5
    maxReplicas: 20
    targetCPU: 60
  
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "512Mi"

ratings:
  replicas: 3
  env:
    LOG_LEVEL: warn
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "1000m"
      memory: "512Mi"
  hpa:
    minReplicas: 3
    maxReplicas: 10

payment:
  replicas: 5                    # Critical service
  env:
    LOG_LEVEL: warn
  resources:
    requests:
      cpu: "300m"
      memory: "512Mi"
    limits:
      cpu: "2000m"
      memory: "2Gi"
  hpa:
    minReplicas: 5
    maxReplicas: 20
    targetCPU: 50                # Scale very aggressively

# Databases: High storage and resources
mysql:
  replicas: 3                    # ← Multi-replica for HA
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        storageClassName: fast-ssd # ← Production storage class
        resources:
          requests:
            storage: 100Gi       # ← Large storage

mongodb:
  replicas: 3
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        storageClassName: fast-ssd
        resources:
          requests:
            storage: 100Gi

redis:
  replicas: 3
  resources:
    requests:
      cpu: "200m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
```

---

## Complete Examples

### Scenario 1: Only Change Replicas

**Base (values.yaml):**
```yaml
user:
  name: user
  replicas: 1
  image:
    version: 2.1.0
  resources:
    requests:
      cpu: "100m"
```

**Production Override (values-prod.yaml):**
```yaml
user:
  replicas: 10  # ← Only change this
```

**Result after merge:**
```yaml
user:
  name: user
  replicas: 10        # ← Changed
  image:
    version: 2.1.0    # ← Kept from base
  resources:
    requests:
      cpu: "100m"     # ← Kept from base
```

---

### Scenario 2: Change Nested Values

**Base (values.yaml):**
```yaml
user:
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
```

**Production Override (values-prod.yaml):**
```yaml
user:
  resources:
    requests:
      cpu: "500m"     # ← Only change CPU
    limits:
      memory: "2Gi"   # ← Only change memory limit
```

**Result after merge:**
```yaml
user:
  resources:
    requests:
      cpu: "500m"     # ← Changed
      memory: "128Mi" # ← Kept from base
    limits:
      cpu: "500m"     # ← Kept from base
      memory: "2Gi"   # ← Changed
```

---

### Scenario 3: Add New Values in Environment

**Base (values.yaml):**
```yaml
user:
  env:
    LOG_LEVEL: info
```

**Production Override (values-prod.yaml):**
```yaml
user:
  env:
    LOG_LEVEL: warn
    MONITORING_ENABLED: "true"    # ← Add new env var
    APM_ENDPOINT: "http://apm:8200"
```

**Result after merge:**
```yaml
user:
  env:
    LOG_LEVEL: warn               # ← Changed
    MONITORING_ENABLED: "true"    # ← Added
    APM_ENDPOINT: "http://apm:8200" # ← Added
```

---

## Commands and Workflow

### Development Deployment

```bash
# Deploy with dev values
helm install robot-shop ./robot-shop \
  --namespace robot-shop-dev \
  --create-namespace \
  --values robot-shop/values.yaml \
  --values values-dev.yaml

# Or shorter (base values.yaml is automatic)
helm install robot-shop ./robot-shop \
  -n robot-shop-dev \
  --create-namespace \
  -f values-dev.yaml
```

### Staging Deployment

```bash
helm install robot-shop ./robot-shop \
  -n robot-shop-staging \
  --create-namespace \
  -f values-staging.yaml
```

### Production Deployment

```bash
helm install robot-shop ./robot-shop \
  -n robot-shop-prod \
  --create-namespace \
  -f values-prod.yaml
```

---

### Multiple Values Files (Layered)

```bash
# Base + Environment + Secrets
helm install robot-shop ./robot-shop \
  -n robot-shop-prod \
  -f robot-shop/values.yaml \     # Base
  -f values-prod.yaml \           # Production overrides
  -f values-prod-secrets.yaml     # Production secrets (not in Git)
```

**Order matters**: Later files override earlier files.

---

### Command-Line Overrides

```bash
# Production + temporary override
helm install robot-shop ./robot-shop \
  -n robot-shop-prod \
  -f values-prod.yaml \
  --set user.replicas=20 \        # Emergency scale up
  --set web.image.version=2.2.0   # Test new version
```

---

### Dry Run to See Final Values

```bash
# See what will be deployed
helm install robot-shop ./robot-shop \
  -n robot-shop-prod \
  -f values-prod.yaml \
  --dry-run \
  --debug

# See specific service final YAML
helm template robot-shop ./robot-shop \
  -f values-prod.yaml \
  --show-only charts/user/templates/deployment.yaml
```

---

### See Computed Values

```bash
# After installation, see actual values used
helm get values robot-shop -n robot-shop-prod

# See all values (including defaults)
helm get values robot-shop -n robot-shop-prod --all

# See values for specific subchart
helm get values robot-shop -n robot-shop-prod -o yaml | yq '.user'
```

---

## Best Practices

### 1. **Keep Base Values Minimal**

```yaml
# robot-shop/values.yaml
# Bare minimum defaults suitable for dev

user:
  replicas: 1         # Smallest safe value
  resources:
    requests:
      cpu: "50m"      # Smallest safe value
      memory: "64Mi"
```

### 2. **Production is Explicit**

```yaml
# values-prod.yaml
# Explicitly set ALL production values
# Don't rely on defaults

user:
  replicas: 5         # Explicit
  resources:
    requests:
      cpu: "500m"     # Explicit
      memory: "1Gi"   # Explicit
```

### 3. **Use Comments to Explain**

```yaml
# values-prod.yaml

user:
  replicas: 5         # HA requirement: min 5 for 99.9% uptime
  
  hpa:
    maxReplicas: 20   # Black Friday traffic: 20x normal
    targetCPU: 60     # Aggressive scaling to maintain latency SLA
```

### 4. **Separate Secrets**

```bash
# Don't put secrets in values files
# Use separate secret management

# values-prod.yaml (in Git)
user:
  env:
    DB_HOST: mysql

# values-prod-secrets.yaml (NOT in Git)
user:
  envFromSecrets:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: password
```

### 5. **Environment File Naming Convention**

```
values-dev.yaml          # Development
values-staging.yaml      # Staging
values-prod.yaml         # Production
values-prod-us-east.yaml # Production US East region
values-prod-eu-west.yaml # Production EU West region
```

### 6. **Validate Before Deploy**

```bash
# 1. Lint
helm lint robot-shop/

# 2. Template (see output)
helm template robot-shop ./robot-shop -f values-prod.yaml

# 3. Dry run
helm install robot-shop ./robot-shop \
  -n robot-shop-prod \
  -f values-prod.yaml \
  --dry-run

# 4. Diff (if chart already installed)
helm diff upgrade robot-shop ./robot-shop \
  -n robot-shop-prod \
  -f values-prod.yaml
```

### 7. **Version Control Strategy**

```bash
git/
├── values-dev.yaml       ← Commit to Git
├── values-staging.yaml   ← Commit to Git
├── values-prod.yaml      ← Commit to Git (no secrets)
└── values-prod-secrets.yaml  ← DO NOT COMMIT (add to .gitignore)
```

---

## Common Patterns

### Pattern 1: Environment Variable Toggle

```yaml
# Base
user:
  env:
    FEATURE_NEW_UI: "false"

# Staging (test new feature)
user:
  env:
    FEATURE_NEW_UI: "true"

# Production (after testing)
user:
  env:
    FEATURE_NEW_UI: "true"
```

### Pattern 2: Resource Scaling by Environment

```yaml
# values-dev.yaml
resources: &small-resources
  requests:
    cpu: "50m"
    memory: "64Mi"
  limits:
    cpu: "200m"
    memory: "128Mi"

# values-staging.yaml
resources: &medium-resources
  requests:
    cpu: "200m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"

# values-prod.yaml
resources: &large-resources
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "2000m"
    memory: "4Gi"
```

### Pattern 3: Conditional Features

```yaml
# values-dev.yaml
debugging:
  enabled: true
  port: 5005

monitoring:
  enabled: false

# values-prod.yaml
debugging:
  enabled: false

monitoring:
  enabled: true
  endpoint: "http://prometheus:9090"
```

---

## Troubleshooting

### Issue: Values not overriding

**Debug:**
```bash
# See final computed values
helm get values robot-shop -n robot-shop-prod --all | grep -A 10 "user:"

# Check file is being loaded
helm install robot-shop ./robot-shop \
  -f values-prod.yaml \
  --dry-run \
  --debug | grep -A 20 "COMPUTED VALUES"
```

### Issue: Unexpected merge behavior

**Deep merge example:**
```yaml
# Base
user:
  env:
    A: "1"
    B: "2"

# Override
user:
  env:
    B: "999"  # ← Replaces B
    C: "3"    # ← Adds C

# Result
user:
  env:
    A: "1"    # ← Kept
    B: "999"  # ← Replaced
    C: "3"    # ← Added
```

---

## Summary

### Key Takeaways

1. **Partial overrides**: Only specify what changes, rest stays default
2. **Deep merge**: Helm intelligently merges nested structures
3. **Multiple files**: `-f file1.yaml -f file2.yaml` (later wins)
4. **Command line**: `--set key=value` (highest priority)
5. **Environment files**: Keep separate for dev/staging/prod
6. **Secrets separate**: Never commit secrets to Git
7. **Validate first**: `helm template` and `--dry-run` before deploy

### Deployment Commands Summary

```bash
# Development
helm install robot-shop ./robot-shop -n dev -f values-dev.yaml

# Staging
helm install robot-shop ./robot-shop -n staging -f values-staging.yaml

# Production
helm install robot-shop ./robot-shop -n prod -f values-prod.yaml

# Production with secrets (not in Git)
helm install robot-shop ./robot-shop -n prod \
  -f values-prod.yaml \
  -f values-prod-secrets.yaml
```
