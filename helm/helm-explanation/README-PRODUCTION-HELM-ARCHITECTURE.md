# Production Helm Architecture for Microservices

**A comprehensive guide to building scalable Helm charts for production microservices applications**

---

## Table of Contents

1. [Understanding the Problem Space](#understanding-the-problem-space)
2. [Architectural Decisions](#architectural-decisions)
3. [Chart Structure Patterns](#chart-structure-patterns)
4. [Dependency Management](#dependency-management)
5. [Configuration Strategy](#configuration-strategy)
6. [Scaling Considerations](#scaling-considerations)
7. [Production Best Practices](#production-best-practices)

---

## Understanding the Problem Space

### Our Application: Robot-Shop

Robot-Shop consists of **12 services** with different characteristics:

**Frontend & API Services:**
- `web`: Nginx reverse proxy, exposed on port 8080
- `catalogue`: Node.js service, retrieves product information from MongoDB
- `user`: Node.js service, manages users and sessions with MongoDB and Redis
- `cart`: Node.js service, shopping cart with Redis backend
- `shipping`: Java/Spring Boot service, calculates shipping with MySQL
- `payment`: Python/Flask service, processes payments via RabbitMQ
- `ratings`: PHP service, manages product ratings with MySQL
- `dispatch`: Go service, consumes messages and processes orders

**Data Stores:**
- `mongodb`: Stores catalogue and user data (StatefulSet)
- `mysql`: Stores shipping and ratings data (StatefulSet)
- `redis`: Caches cart and session data (StatefulSet)

**Message Broker:**
- `rabbitmq`: Message broker for async processing (StatefulSet)

### Key Characteristics

| Service | Type | Port | Dependencies | State |
|---------|------|------|--------------|-------|
| web | Nginx | 8080 | catalogue, user, cart | Stateless |
| catalogue | Node.js | 8080 | mongodb | Stateless |
| user | Node.js | 8080 | mongodb, redis | Stateless |
| cart | Node.js | 8080 | redis | Stateless |
| shipping | Java | 8080 | mysql | Stateless |
| payment | Python | 8080 | rabbitmq | Stateless |
| ratings | PHP | 8080 | mysql | Stateless |
| dispatch | Go | 8080 | rabbitmq | Stateless |
| mongodb | Database | 27017 | - | **Stateful** |
| mysql | Database | 3306 | - | **Stateful** |
| redis | Cache | 6379 | - | **Stateful** |
| rabbitmq | Message Queue | 5672 | - | **Stateful** |

---

## Architectural Decisions

### Decision 1: One Chart vs Multiple Charts

#### ❌ Approach 1: Monolithic Chart

```
helm/robot-shop/
  Chart.yaml          # One chart definition
  values.yaml         # ALL configuration here (huge file)
  templates/          # ALL Kubernetes manifests (12+ services)
    web-deployment.yaml
    catalogue-deployment.yaml
    mongodb-statefulset.yaml
    ... (all 12 services × multiple files each)
```

**Pros:**
- ✅ Deploy entire application with one command: `helm install robot-shop`
- ✅ Easy to manage dependencies between services
- ✅ Simple CI/CD pipeline
- ✅ Good for small applications (< 10 services)

**Cons:**
- ❌ Huge `values.yaml` file (gets messy with 42 services)
- ❌ Cannot deploy individual services independently
- ❌ Hard to version services separately
- ❌ Team boundaries blur (who owns what?)
- ❌ All-or-nothing deployments (risky)
- ❌ Difficult to reuse charts across projects

**When to use:** Small applications, PoC/demo environments, tightly coupled services

---

#### ✅ Approach 2: Microservice Charts with Umbrella Chart (Production Standard)

```
helm/
├── robot-shop/                    # UMBRELLA CHART (orchestrator)
│   ├── Chart.yaml                 # Lists dependencies
│   ├── values.yaml                # Global overrides
│   ├── values-dev.yaml            # Dev environment
│   ├── values-staging.yaml        # Staging environment
│   └── values-prod.yaml           # Production environment
│
└── charts/                        # INDIVIDUAL MICROSERVICE CHARTS
    ├── _common/                   # Shared templates (the magic)
    │   └── templates/
    │       ├── _deployment.yaml
    │       ├── _service.yaml
    │       ├── _statefulset.yaml
    │       └── _helpers.tpl
    │
    ├── web/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── ingress.yaml
    │
    ├── catalogue/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── configmap.yaml
    │
    └── ... (all other services)
```

**Pros:**
- ✅ Each team owns their service's chart
- ✅ Deploy individually: `helm install catalogue charts/catalogue/`
- ✅ Deploy all together: `helm install robot-shop helm/robot-shop/`
- ✅ Version services independently
- ✅ Reusable charts across projects
- ✅ Clean separation of concerns
- ✅ Progressive rollouts (deploy 5 services, test, continue)
- ✅ Easier code reviews (smaller changes)

**Cons:**
- ❌ More initial setup effort
- ❌ Need to understand chart dependencies
- ❌ Slightly more complex directory structure

**When to use:** Production applications, 10+ microservices, multiple teams, long-term maintenance

**🎯 Decision: Use Approach 2 for Robot-Shop**

---

### Decision 2: Build vs Use Existing Charts

#### For Infrastructure Services (Backing Services)

**Question:** "Should I build my own MongoDB/MySQL/Redis charts?"

**Answer:** ❌ **NO** - Use battle-tested community charts

**Use Bitnami Charts for:**
- ✅ mongodb
- ✅ mysql  
- ✅ redis
- ✅ rabbitmq

**Why Bitnami?**
1. **Production Hardening**: Security best practices built-in
2. **High Availability**: Primary-replica configurations ready
3. **Backup/Restore**: Built-in mechanisms
4. **Monitoring**: ServiceMonitor for Prometheus included
5. **Regular Updates**: Active maintenance and security patches
6. **Battle-Tested**: Used by thousands of companies
7. **Comprehensive Documentation**: Extensive guides and examples
8. **Configuration Options**: Hundreds of tuneable parameters

**Example: Using Bitnami MongoDB**

Instead of creating 10+ files for MongoDB StatefulSet, Service, ConfigMap, Secret, etc., you do:

```yaml
# helm/robot-shop/Chart.yaml
dependencies:
  - name: mongodb
    version: "13.6.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: mongodb.enabled
```

Then configure it:

```yaml
# helm/robot-shop/values.yaml
mongodb:
  enabled: true
  auth:
    rootPassword: "secret"
    database: "catalogue"
  persistence:
    size: 20Gi
  replicaCount: 3  # High availability with 3 replicas
```

**What you get automatically:**
- StatefulSet with proper volume management
- Headless Service for stable network identity
- Init containers for replica setup
- Health checks (liveness, readiness)
- Resource limits
- Security contexts
- Backup configurations
- Monitoring endpoints

---

#### For Application Services (Your Business Logic)

**Question:** "Should I build charts for my custom applications?"

**Answer:** ✅ **YES** - Always build your own charts

**Reasons:**
1. Unique deployment requirements
2. Custom environment variables
3. Specific resource needs
4. Your team owns the lifecycle
5. Application-specific health checks
6. Custom init containers
7. Specific security policies

---

## Chart Structure Patterns

### The Power of Template Inheritance

**Problem:** With 42 microservices, you'll notice 80% of manifests look identical.

**Bad Solution:** Copy-paste 42 times (maintenance nightmare)

**Good Solution:** Create reusable templates in `_common/` chart

### Example: Deployment Template

#### ❌ Without Templating (Bad)

You write this 42 times:

```yaml
# charts/catalogue/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue
  labels:
    app: catalogue
    tier: backend
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalogue
  template:
    metadata:
      labels:
        app: catalogue
    spec:
      containers:
      - name: catalogue
        image: robotshop/catalogue:1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: mongodb
        - name: DB_NAME
          value: catalogue
```

Then copy for `user`, `cart`, `payment`, etc. - changing only a few values each time.

**Problems:**
- Need a bug fix in all deployments? Edit 42 files
- Want to add a security context? Edit 42 files
- New team member? 42 files to understand

---

#### ✅ With Templating (Good)

**Step 1:** Create common template once:

```yaml
# charts/_common/templates/_deployment.yaml
{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
    spec:
      containers:
      - name: {{ .Values.name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - containerPort: {{ .Values.service.port }}
        {{- if .Values.env }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
{{- end -}}
```

**Step 2:** Each service uses the template:

```yaml
# charts/catalogue/templates/deployment.yaml
{{- include "common.deployment" . -}}
```

That's it! One line.

**Step 3:** Configure via values:

```yaml
# charts/catalogue/values.yaml
name: catalogue
replicaCount: 2
image:
  repository: robotshop/catalogue
  tag: "1.0.0"
service:
  port: 8080
env:
  DB_HOST: mongodb
  DB_NAME: catalogue
```

**Benefits:**
- ✅ Add a feature to common template → all 42 services get it
- ✅ Bug fix in one place
- ✅ Consistent deployments across all services
- ✅ New service? Copy 3 files (Chart.yaml, values.yaml, templates/deployment.yaml)
- ✅ Easy to review changes (just values changed)

---

## Dependency Management

### Service Dependencies in Robot-Shop

```
web → catalogue, user, cart
    ↓
catalogue → mongodb
user → mongodb, redis
cart → redis
shipping → mysql
payment → rabbitmq
dispatch → rabbitmq
ratings → mysql
```

### Problem: Service Start Order

**Scenario:** `catalogue` pod starts before `mongodb` is ready

**Result:**
```
catalogue | Error: connect ECONNREFUSED mongodb:27017
catalogue | Retrying in 5s...
catalogue | Error: connect ECONNREFUSED mongodb:27017
catalogue | CrashLoopBackOff
```

### Solution 1: Init Containers (Wait for Dependencies)

Init containers run **before** your main container. They must complete successfully.

```yaml
# charts/catalogue/templates/deployment.yaml
spec:
  template:
    spec:
      initContainers:
      # Wait for MongoDB to be ready
      - name: wait-for-mongodb
        image: busybox:1.35
        command: ['sh', '-c']
        args:
          - |
            until nc -z mongodb 27017; do
              echo "Waiting for MongoDB on mongodb:27017..."
              sleep 2
            done
            echo "MongoDB is ready!"
      
      # Main container starts only after init container succeeds
      containers:
      - name: catalogue
        image: robotshop/catalogue:1.0.0
        # ...
```

**How it works:**
1. Kubernetes starts the init container
2. `nc -z mongodb 27017` checks if port is open
3. If not ready: sleeps 2 seconds, tries again
4. Once ready: init container exits successfully
5. Main container starts

---

### Solution 2: Helm Chart Dependencies

In the umbrella chart, define the deployment order:

```yaml
# helm/robot-shop/Chart.yaml
dependencies:
  # Infrastructure first
  - name: mongodb
    version: "13.6.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: mongodb.enabled
  
  - name: redis
    version: "17.3.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
  
  # Application services after
  - name: catalogue
    version: "1.0.0"
    repository: "file://../charts/catalogue"
    condition: catalogue.enabled
    # Note: Helm doesn't guarantee order, use init containers for runtime checks
```

**Important:** Helm dependency order affects **template rendering**, not **pod startup order**. Always use init containers for runtime dependency checks.

---

## Configuration Strategy

### The Values Hierarchy

Helm merges values from multiple sources (lowest to highest priority):

```
1. Chart defaults        (charts/catalogue/values.yaml)
2. Parent chart values   (helm/robot-shop/values.yaml)
3. Environment file      (values-prod.yaml)
4. Command-line          (--set, --values)
```

### Example: Catalogue Service Configuration

**Level 1: Chart Defaults** (Development-friendly)

```yaml
# charts/catalogue/values.yaml
name: catalogue
replicaCount: 1                    # Single replica for dev
image:
  repository: robotshop/catalogue
  tag: "latest"                    # Latest for dev
  pullPolicy: IfNotPresent
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
env:
  LOG_LEVEL: "debug"               # Verbose logging for dev
  NODE_ENV: "development"
```

---

**Level 2: Umbrella Chart** (Application-wide overrides)

```yaml
# helm/robot-shop/values.yaml
global:
  imagePullPolicy: Always
  environment: production

# Override specific services
catalogue:
  replicaCount: 3                  # Production needs 3 replicas
  image:
    tag: "1.2.5"                   # Specific stable version
  env:
    LOG_LEVEL: "info"              # Less verbose for prod
    NODE_ENV: "production"
    DB_HOST: "mongodb.robot-shop.svc.cluster.local"
    DB_NAME: "catalogue_prod"

user:
  replicaCount: 5
  env:
    DB_HOST: "mongodb.robot-shop.svc.cluster.local"
    REDIS_HOST: "redis-master.robot-shop.svc.cluster.local"
```

---

**Level 3: Environment File** (Environment-specific)

```yaml
# values-prod.yaml
catalogue:
  resources:
    limits:
      memory: "512Mi"              # More memory in prod
      cpu: "500m"
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70

mongodb:
  persistence:
    size: 100Gi                    # Larger disk in prod
  replicaCount: 3                  # HA configuration
```

---

**Level 4: Runtime Override** (Hotfix/testing)

```bash
helm upgrade robot-shop ./helm/robot-shop \
  -f values-prod.yaml \
  --set catalogue.image.tag=1.2.6 \          # Emergency patch
  --set catalogue.replicaCount=5              # Scaling up
```

**Final Result for `catalogue` deployment:**
- `replicaCount`: 5 (from --set)
- `image.tag`: 1.2.6 (from --set)
- `resources.limits.memory`: 512Mi (from values-prod.yaml)
- `env.LOG_LEVEL`: info (from robot-shop/values.yaml)
- `image.repository`: robotshop/catalogue (from chart default)

---

### Environment Variables & Secrets

#### Type 1: Non-Sensitive Configuration (ConfigMap)

```yaml
# charts/catalogue/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.name }}-config
data:
  LOG_LEVEL: {{ .Values.env.LOG_LEVEL | quote }}
  NODE_ENV: {{ .Values.env.NODE_ENV | quote }}
  DB_NAME: {{ .Values.env.DB_NAME | quote }}
```

Usage in deployment:
```yaml
envFrom:
- configMapRef:
    name: catalogue-config
```

---

#### Type 2: Sensitive Data (Secret)

```yaml
# charts/catalogue/templates/secret.yaml
{{- if .Values.secrets }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.name }}-secret
type: Opaque
stringData:
  {{- range $key, $value := .Values.secrets }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
```

Values:
```yaml
# values.yaml
secrets:
  DB_PASSWORD: "secure123"
  API_KEY: "xyz789"
```

Usage:
```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: catalogue-secret
      key: DB_PASSWORD
```

**⚠️ Production Warning:** Never store secrets in Git! Use:
- External secret management (Vault, AWS Secrets Manager)
- Sealed Secrets
- SOPS for encrypted values
- CI/CD secrets injection

---

## Scaling Considerations

### Scaling to 42+ Microservices

#### Challenge 1: Chart Maintenance

**Problem:** Creating 42 charts manually is tedious and error-prone.

**Solution:** Chart Generator Script

```bash
#!/bin/bash
# scripts/create-service-chart.sh

SERVICE_NAME=$1
SERVICE_TYPE=$2  # deployment or statefulset
PORT=$3
DEPENDENCIES=$4  # comma-separated: "mongodb,redis"

mkdir -p charts/${SERVICE_NAME}/templates

# Create Chart.yaml
cat > charts/${SERVICE_NAME}/Chart.yaml <<EOF
apiVersion: v2
name: ${SERVICE_NAME}
description: ${SERVICE_NAME} service for Robot-Shop
version: 1.0.0
appVersion: "1.0.0"
dependencies:
  - name: common
    version: "1.0.0"
    repository: "file://../_common"
EOF

# Create values.yaml
cat > charts/${SERVICE_NAME}/values.yaml <<EOF
name: ${SERVICE_NAME}
replicaCount: 1
image:
  repository: robotshop/${SERVICE_NAME}
  tag: "latest"
  pullPolicy: IfNotPresent
service:
  type: ClusterIP
  port: ${PORT}
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
EOF

# Create deployment using common template
echo "{{- include \"common.deployment\" . -}}" > charts/${SERVICE_NAME}/templates/deployment.yaml

# Create service
echo "{{- include \"common.service\" . -}}" > charts/${SERVICE_NAME}/templates/service.yaml

echo "✅ Created chart for ${SERVICE_NAME}"
```

**Usage:**
```bash
./scripts/create-service-chart.sh catalogue deployment 8080 "mongodb"
./scripts/create-service-chart.sh user deployment 8080 "mongodb,redis"
./scripts/create-service-chart.sh payment deployment 8080 "rabbitmq"
# ... repeat for all services
```

---

#### Challenge 2: Service Discovery & Inventory

**Problem:** With 42 services, how do you know what's deployed, versions, dependencies?

**Solution:** Service Matrix (YAML-based inventory)

```yaml
# service-matrix.yaml
services:
  # Frontend
  - name: web
    type: deployment
    tier: frontend
    port: 8080
    exposed: true  # Has Ingress
    dependencies: []
    env_vars:
      - CATALOGUE_HOST
      - USER_HOST
      - CART_HOST
  
  # Backend Services
  - name: catalogue
    type: deployment
    tier: backend
    port: 8080
    dependencies:
      - mongodb
    env_vars:
      - DB_HOST: mongodb
      - DB_NAME: catalogue
      - DB_PORT: "27017"
  
  - name: user
    type: deployment
    tier: backend
    port: 8080
    dependencies:
      - mongodb
      - redis
    env_vars:
      - DB_HOST: mongodb
      - DB_NAME: users
      - REDIS_HOST: redis-master
  
  - name: cart
    type: deployment
    tier: backend
    port: 8080
    dependencies:
      - redis
    env_vars:
      - REDIS_HOST: redis-master
  
  - name: shipping
    type: deployment
    tier: backend
    port: 8080
    language: java
    dependencies:
      - mysql
    env_vars:
      - SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/shipping
  
  - name: payment
    type: deployment
    tier: backend
    port: 8080
    language: python
    dependencies:
      - rabbitmq
    env_vars:
      - AMQP_HOST: rabbitmq
  
  - name: ratings
    type: deployment
    tier: backend
    port: 8080
    language: php
    dependencies:
      - mysql
    env_vars:
      - MYSQL_HOST: mysql
      - MYSQL_DATABASE: ratings
  
  - name: dispatch
    type: deployment
    tier: backend
    port: 8080
    language: go
    dependencies:
      - rabbitmq
    env_vars:
      - AMQP_URL: amqp://rabbitmq:5672
  
  # Data Stores
  - name: mongodb
    type: statefulset
    tier: database
    port: 27017
    chart_source: bitnami
    dependencies: []
  
  - name: mysql
    type: statefulset
    tier: database
    port: 3306
    chart_source: bitnami
    dependencies: []
  
  - name: redis
    type: statefulset
    tier: database
    port: 6379
    chart_source: bitnami
    dependencies: []
  
  - name: rabbitmq
    type: statefulset
    tier: messaging
    port: 5672
    chart_source: bitnami
    dependencies: []
```

**Benefits:**
- 📋 Documentation as code
- 🔍 Easy to see dependencies
- 🤖 Can generate Helm charts from this
- 📊 Generate architecture diagrams
- 🔒 Validate network policies match dependencies

---

#### Challenge 3: GitOps for 42 Services

**Problem:** Manual helm commands don't scale. Need declarative, automated management.

**Solution:** ArgoCD Applications

Directory structure:
```
gitops-repo/
├── argocd/
│   ├── applications/
│   │   ├── infrastructure.yaml     # All databases/message brokers
│   │   ├── backend-services.yaml   # All backend APIs
│   │   └── frontend.yaml           # Web service
│   │
│   └── app-of-apps.yaml            # Master application
│
└── helm/
    └── robot-shop/                 # Your helm charts
```

**Master Application (App of Apps pattern):**

```yaml
# argocd/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: robot-shop
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/yourorg/robot-shop
    targetRevision: main
    path: argocd/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Infrastructure Application:**

```yaml
# argocd/applications/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
spec:
  generators:
  - list:
      elements:
      - name: mongodb
        chart: mongodb
        version: "13.6.0"
      - name: mysql
        chart: mysql
        version: "9.4.0"
      - name: redis
        chart: redis
        version: "17.3.0"
      - name: rabbitmq
        chart: rabbitmq
        version: "11.1.0"
  
  template:
    metadata:
      name: '{{name}}'
    spec:
      project: default
      source:
        repoURL: https://charts.bitnami.com/bitnami
        chart: '{{chart}}'
        targetRevision: '{{version}}'
        helm:
          valueFiles:
            - values-prod.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: robot-shop
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

**Benefits:**
- ✅ Declare once, auto-deploy
- ✅ Git is source of truth
- ✅ Rollback = git revert
- ✅ Progressive rollout
- ✅ Audit trail
- ✅ Self-healing (if manual change, ArgoCD reverts)

---

## Production Best Practices

### 1. Stateful vs Stateless Deployments

#### Stateless Services (Deployment)

**Characteristics:**
- No persistent data on pod
- Pods are interchangeable
- Can scale horizontally easily
- Rolling updates are safe

**Services:** web, catalogue, user, cart, shipping, payment, ratings, dispatch

**Key Configurations:**

```yaml
# Deployment
replicas: 3                        # Multiple replicas
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1                    # 1 extra pod during update
    maxUnavailable: 0              # Zero downtime

# Readiness probe (when to receive traffic)
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5

# Liveness probe (when to restart)
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

#### Stateful Services (StatefulSet)

**Characteristics:**
- Persistent data attached to pod
- Stable network identity (mongodb-0, mongodb-1)
- Ordered deployment/scaling
- Volumes follow the pod

**Services:** mongodb, mysql, redis, rabbitmq

**Key Configurations:**

```yaml
# StatefulSet
replicas: 3
serviceName: mongodb               # Headless service
podManagementPolicy: OrderedReady  # Deploy in order: 0, 1, 2

# Volume Claims (storage per pod)
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 20Gi
    storageClassName: fast-ssd     # Performance matters for databases
```

**Why use Bitnami charts?** They handle:
- Primary-replica replication
- Automatic failover
- Backup configurations
- Init containers for setup
- Security hardening

---

### 2. Resource Management

**Problem:** Without resource limits, one service can starve others.

**Solution:** Define requests and limits for every service.

```yaml
resources:
  requests:                        # Guaranteed resources (scheduler uses this)
    memory: "256Mi"
    cpu: "200m"
  limits:                          # Maximum allowed (pod killed if exceeded)
    memory: "512Mi"
    cpu: "500m"
```

**Guidelines:**
- **CPU**: 1000m = 1 core. Start with 100-200m for APIs, tune based on metrics.
- **Memory**: Start with 256Mi-512Mi, monitor actual usage, adjust.
- **Requests < Limits**: Allows bursting while guaranteeing baseline.

**Recommended by Service Type:**

| Service Type | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------------|-------------|-----------|----------------|--------------|
| Node.js API | 100m | 500m | 256Mi | 512Mi |
| Java API | 250m | 1000m | 512Mi | 1Gi |
| Python API | 100m | 500m | 256Mi | 512Mi |
| Nginx | 50m | 200m | 128Mi | 256Mi |
| MongoDB | 500m | 2000m | 1Gi | 2Gi |
| MySQL | 500m | 2000m | 1Gi | 2Gi |

---

### 3. Health Checks

**Liveness Probe:** "Is the application alive?" (restart if fails)

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30          # Wait 30s for app to start
  periodSeconds: 10                # Check every 10s
  timeoutSeconds: 5                # Timeout after 5s
  failureThreshold: 3              # Restart after 3 failures
```

**Readiness Probe:** "Is the application ready for traffic?" (remove from service if fails)

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  successThreshold: 1              # 1 success = ready
  failureThreshold: 3              # Remove from service after 3 failures
```

**Startup Probe:** For slow-starting apps (Java with long init)

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30             # 30 attempts
  periodSeconds: 10                # Every 10s = 5 minutes total
```

---

### 4. Autoscaling (HPA)

**Horizontal Pod Autoscaler:** Automatically scale replicas based on metrics.

```yaml
# charts/catalogue/templates/hpa.yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Values.name }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Values.name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
{{- end }}
```

Configuration:
```yaml
# values-prod.yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

---

### 5. Network Policies

**Zero Trust:** Only allow required connections.

```yaml
# charts/catalogue/templates/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: catalogue-policy
spec:
  podSelector:
    matchLabels:
      app: catalogue
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow traffic from web service
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow MongoDB
  - to:
    - podSelector:
        matchLabels:
          app: mongodb
    ports:
    - protocol: TCP
      port: 27017
```

---

## Summary: What to Build from Scratch

### ❌ Don't Build (Use Dependencies)

Use Bitnami charts as dependencies:
- mongodb
- mysql
- redis
- rabbitmq

**Benefit:** Production-ready, maintained, secure.

---

### ✅ Build Yourself

Create individual charts for:
- web
- catalogue
- user
- cart
- shipping
- payment
- ratings
- dispatch

**Benefit:** Custom business logic, team ownership, specific configurations.

---

### 🛠️ Create Once, Reuse Forever

Build `_common` chart with templates for:
- Deployments
- Services
- StatefulSets
- ConfigMaps
- Secrets
- Init containers
- Network policies
- HPA
- Ingress

**Benefit:** Change once, all services benefit. Scales to 100+ microservices.

---

## Next Steps

1. **Create the `_common` templates** - The foundation for all services
2. **Build one complete service chart** - Learn the patterns (e.g., catalogue)
3. **Set up umbrella chart** - Wire dependencies together
4. **Deploy to production** - Complete workflow

See [README-HELM-TEMPLATES-GUIDE.md](./README-HELM-TEMPLATES-GUIDE.md) for detailed template syntax and examples.

---

## Directory Structure Summary

```
helm/
├── README-PRODUCTION-HELM-ARCHITECTURE.md    # This file
├── README-HELM-TEMPLATES-GUIDE.md            # Template syntax guide
├── robot-shop/                               # Umbrella chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   └── values-prod.yaml
└── charts/
    ├── _common/                              # Shared templates
    │   ├── Chart.yaml
    │   └── templates/
    │       ├── _deployment.yaml
    │       ├── _service.yaml
    │       ├── _statefulset.yaml
    │       ├── _configmap.yaml
    │       ├── _secret.yaml
    │       ├── _ingress.yaml
    │       ├── _hpa.yaml
    │       ├── _networkpolicy.yaml
    │       └── _helpers.tpl
    │
    ├── web/                                  # Service charts
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── ingress.yaml
    │
    ├── catalogue/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── deployment.yaml
    │       ├── service.yaml
    │       └── configmap.yaml
    │
    └── ... (all other services)
```

---

**Next:** Read [README-HELM-TEMPLATES-GUIDE.md](./README-HELM-TEMPLATES-GUIDE.md) to learn template syntax line-by-line.
