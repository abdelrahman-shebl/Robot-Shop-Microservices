# Multi-Environment Values Guide
## Managing Dev, Staging, and Production Configurations

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Values Hierarchy](#values-hierarchy)
3. [Creating Environment-Specific Values](#creating-environment-specific-values)
4. [Partial Overrides (Modify Only Certain Values)](#partial-overrides)
5. [Complete Examples](#complete-examples)
6. [Commands and Workflow](#commands-and-workflow)
7. [Best Practices](#best-practices)

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
