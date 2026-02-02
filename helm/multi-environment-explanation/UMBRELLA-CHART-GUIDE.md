# Umbrella Chart Guide: Referencing Subcharts
## Complete Guide to robot-shop Main Chart with Dependencies

---

## Table of Contents

1. [What is an Umbrella Chart](#what-is-an-umbrella-chart)
2. [Directory Structure](#directory-structure)
3. [How to Reference Subcharts](#how-to-reference-subcharts)
4. [Chart.yaml with Dependencies](#chartyaml-with-dependencies)
5. [values.yaml for All Services](#valuesyaml-for-all-services)
6. [Overriding Subchart Values](#overriding-subchart-values)
7. [Commands and Workflow](#commands-and-workflow)

---

## What is an Umbrella Chart

An **umbrella chart** (also called parent chart) deploys **multiple subcharts** with **one command**.

### Without Umbrella Chart (Manual)
```bash
helm install user ./user -n robot-shop
helm install web ./web -n robot-shop
helm install mysql ./mysql -n robot-shop
helm install ratings ./ratings -n robot-shop
helm install dispatch ./dispatch -n robot-shop
helm install catalogue ./catalogue -n robot-shop
helm install payment ./payment -n robot-shop
helm install cart ./cart -n robot-shop
helm install shipping ./shipping -n robot-shop
helm install mongodb ./mongodb -n robot-shop
helm install redis ./redis -n robot-shop
helm install rabbitmq ./rabbitmq -n robot-shop
```

**Problems:**
- 12 separate commands
- No coordination between deployments
- Hard to manage versions
- Can't deploy atomically

### With Umbrella Chart (Automated)
```bash
helm install robot-shop ./robot-shop -n robot-shop
```

**Benefits:**
- ✅ One command deploys everything
- ✅ Atomic deployment (all or nothing)
- ✅ Coordinated versions
- ✅ Single configuration file
- ✅ Easy rollback for entire stack

---

## Directory Structure

```
helm/
├── robot-shop/                    ← Umbrella chart (main)
│   ├── Chart.yaml                 ← Defines dependencies
│   ├── values.yaml                ← Configuration for ALL subcharts
│   ├── charts/                    ← Subcharts live here
│   │   ├── _common/              ← Common templates
│   │   ├── user/
│   │   ├── web/
│   │   ├── mysql/
│   │   ├── ratings/
│   │   ├── dispatch/
│   │   ├── catalogue/
│   │   ├── payment/
│   │   ├── cart/
│   │   ├── shipping/
│   │   ├── mongodb/
│   │   ├── redis/
│   │   └── rabbitmq/
│   └── templates/
│       └── NOTES.txt             ← Post-install message
│
├── values-dev.yaml               ← Dev environment overrides
├── values-prod.yaml              ← Prod environment overrides
└── values-staging.yaml           ← Staging environment overrides
```

---

## How to Reference Subcharts

There are **two ways** to include subcharts in an umbrella chart:

### Method 1: Local Charts (Recommended)
Charts live in `robot-shop/charts/` directory.

### Method 2: Chart Dependencies
Charts referenced in `Chart.yaml` and downloaded.

We'll use **Method 1** since your charts are already in `charts/` directory.

---

## Chart.yaml with Dependencies

### Current Structure (Local Charts)

Since your charts are already in `robot-shop/charts/`, Helm automatically recognizes them as subcharts.

File: `robot-shop/Chart.yaml`

```yaml
apiVersion: v2
name: robot-shop
description: A complete microservices application
type: application
version: 1.0.0
appVersion: "2.1.0"

# Optional: Metadata
keywords:
  - microservices
  - e-commerce
  - demo
home: https://github.com/your-org/robot-shop
sources:
  - https://github.com/your-org/robot-shop
maintainers:
  - name: Your Name
    email: your.email@example.com

# Dependencies (optional - if you want to pull from chart repos)
# dependencies:
#   - name: redis
#     version: 17.x.x
#     repository: https://charts.bitnami.com/bitnami
#     condition: redis.enabled
```

**Key Points:**
- `apiVersion: v2`: Helm 3 format
- `type: application`: This is a deployable application
- `version`: Umbrella chart version (increment when you change umbrella)
- `appVersion`: Application version (robot-shop version)

---

## values.yaml for All Services

The umbrella chart's `values.yaml` contains configuration for **ALL subcharts**.

### Structure Pattern

```yaml
# Subchart name as key
user:
  # All values for user chart
  name: user
  tier: backend
  ...

web:
  # All values for web chart
  name: web
  tier: frontend
  ...

mysql:
  # All values for mysql chart
  ...
```

### Complete Example

File: `robot-shop/values.yaml`

```yaml
# ============================================
# Robot Shop Umbrella Chart Values
# ============================================

# Global values (available to all subcharts)
global:
  namespace: robot-shop
  imageRegistry: robotshop
  imagePullPolicy: IfNotPresent
  
  # Common labels
  labels:
    app.kubernetes.io/managed-by: helm
    app.kubernetes.io/part-of: robot-shop
  
  # Security defaults
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 3000

# ============================================
# Frontend Services
# ============================================

web:
  enabled: true
  name: web
  tier: frontend
  
  image:
    repository: robotshop
    name: rs-web
    version: 2.1.0
  
  port: 8080
  
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"
  
  livenessProbe:
    httpGet:
      path: /nginx_status
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
  
  readinessProbe:
    httpGet:
      path: /nginx_status
      port: 8080
    initialDelaySeconds: 10
    periodSeconds: 5
  
  service:
    port: 8080
  
  ingress:
    host: robot-shop.example.com
  
  hpa:
    minReplicas: 2
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80
  
  networkPolicy:
    policyTypes:
      - Ingress
      - Egress
    ingress:
      - from:
        - podSelector:
            matchLabels:
              app: ingress
        ports:
        - protocol: TCP
          port: 8080
    egress:
      - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
        ports:
        - protocol: TCP
          port: 53
        - protocol: UDP
          port: 53
      - to:
        - podSelector:
            matchLabels:
              app: catalogue
        - podSelector:
            matchLabels:
              app: user
        - podSelector:
            matchLabels:
              app: cart
        ports:
        - protocol: TCP
          port: 8080

# ============================================
# Backend Services
# ============================================

user:
  enabled: true
  name: user
  tier: backend
  
  image:
    repository: robotshop
    name: user
    version: 2.1.0
  
  port: 8080
  
  env:
    MONGO_HOST: mongodb
    LOG_LEVEL: info
  
  envFromSecrets:
    - name: MONGO_USER
      valueFrom:
        secretKeyRef:
          key: MONGO_USER
          name: mongo-secrets
    - name: MONGO_PASSWORD
      valueFrom:
        secretKeyRef:
          key: MONGO_PASSWORD
          name: mongo-secrets
  
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"
  
  service:
    port: 8080
  
  hpa:
    minReplicas: 2
    maxReplicas: 8
    targetCPU: 70
    targetMemory: 80
  
  networkPolicy:
    policyTypes:
      - Ingress
      - Egress
    ingress:
      - from:
        - podSelector:
            matchLabels:
              app: web
        ports:
        - protocol: TCP
          port: 8080
    egress:
      - to:
        - podSelector:
            matchLabels:
              app: mongodb
        ports:
        - protocol: TCP
          port: 27017

ratings:
  enabled: true
  name: ratings
  tier: backend
  
  image:
    repository: robotshop
    name: ratings
    version: 2.1.0
  
  port: 80
  
  env:
    MYSQL_HOST: mysql
    LOG_LEVEL: info
  
  envFromSecrets:
    - name: MYSQL_USER
      valueFrom:
        secretKeyRef:
          key: MYSQL_USER
          name: mysql-secrets
    - name: MYSQL_PASSWORD
      valueFrom:
        secretKeyRef:
          key: MYSQL_PASSWORD
          name: mysql-secrets
  
  capabilities:
    add:
      - NET_BIND_SERVICE
  
  resources:
    requests:
      cpu: "150m"
      memory: "256Mi"
    limits:
      cpu: "750m"
      memory: "512Mi"
  
  service:
    port: 80
  
  hpa:
    minReplicas: 2
    maxReplicas: 6
    targetCPU: 70
    targetMemory: 80

dispatch:
  enabled: true
  name: dispatch
  tier: message-queue
  
  image:
    repository: robotshop
    name: dispatch
    version: 2.1.0
  
  port: 8080
  
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"
  
  service:
    port: 8080
  
  hpa:
    minReplicas: 1
    maxReplicas: 5
    targetCPU: 70
    targetMemory: 80

# ============================================
# Database Services
# ============================================

mysql:
  enabled: true
  name: mysql
  tier: database
  replicas: 1
  serviceName: mysql
  
  image:
    repository: mysql
    name: mysql
    version: "8.0"
  
  port: 3306
  
  envFrom:
    - secretRef:
        name: mysql-secrets
  
  capabilities:
    add:
      - NET_ADMIN
  
  service:
    port: 3306
  
  volumeMounts:
    - name: mysql-data
      mountPath: /var/lib/mysql/
  
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 10Gi
  
  networkPolicy:
    policyTypes:
      - Ingress
      - Egress
    ingress:
      - from:
        - podSelector:
            matchLabels:
              app: ratings
        - podSelector:
            matchLabels:
              app: shipping
        ports:
        - protocol: TCP
          port: 3306

mongodb:
  enabled: true
  name: mongodb
  tier: database
  replicas: 1
  serviceName: mongodb
  
  image:
    repository: mongo
    name: mongo
    version: "5.0"
  
  port: 27017
  
  envFrom:
    - secretRef:
        name: mongodb-secrets
  
  service:
    port: 27017
  
  volumeMounts:
    - name: mongodb-data
      mountPath: /data/db
  
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 10Gi

# ... continue for other services (catalogue, payment, cart, shipping, redis, rabbitmq)
```

---

## Overriding Subchart Values

### How It Works

```
robot-shop/values.yaml
        ↓
   user: {...}      ← Overrides user/values.yaml
        ↓
user/values.yaml    ← Default values (if not overridden)
```

### Example: Different Values per Service

```yaml
# robot-shop/values.yaml

user:
  name: user
  replicas: 3          # ← Overrides user chart default
  hpa:
    maxReplicas: 10    # ← Overrides user chart default

ratings:
  name: ratings
  replicas: 2          # ← Different from user
  hpa:
    maxReplicas: 6     # ← Different from user
```

### Accessing Global Values in Subcharts

In subchart templates, access global values:

```yaml
# user/templates/deployment.yaml
namespace: {{ .Values.global.namespace }}
imagePullPolicy: {{ .Values.global.imagePullPolicy }}
```

---

## Commands and Workflow

### 1. Create Secrets First

```bash
kubectl create namespace robot-shop

# Create all secrets
kubectl create secret generic mongodb-secrets \
  --from-literal=username=admin \
  --from-literal=password=SecurePassword123! \
  -n robot-shop

kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=SecurePassword456! \
  -n robot-shop

kubectl create secret generic redis-secrets \
  --from-literal=password=RedisPassword789! \
  -n robot-shop

kubectl create secret generic rabbitmq-secrets \
  --from-literal=username=admin \
  --from-literal=password=RabbitPassword012! \
  -n robot-shop
```

### 2. Validate Umbrella Chart

```bash
cd /home/abdelrahman/Desktop/DevOps/robot-shop/helm

# Lint umbrella chart (checks all subcharts)
helm lint robot-shop/

# Dry run to see what will be deployed
helm install robot-shop ./robot-shop \
  --namespace robot-shop \
  --dry-run \
  --debug
```

### 3. Install Umbrella Chart

```bash
# Install everything with one command
helm install robot-shop ./robot-shop \
  --namespace robot-shop \
  --create-namespace
```

### 4. Check Deployment

```bash
# List all releases
helm list -n robot-shop

# Check all pods
kubectl get pods -n robot-shop

# Check all services
kubectl get svc -n robot-shop

# Check HPAs
kubectl get hpa -n robot-shop

# Check NetworkPolicies
kubectl get networkpolicies -n robot-shop
```

### 5. Upgrade Umbrella Chart

```bash
# Make changes to robot-shop/values.yaml
vim robot-shop/values.yaml

# Upgrade
helm upgrade robot-shop ./robot-shop \
  --namespace robot-shop
```

### 6. Enable/Disable Subcharts

```yaml
# robot-shop/values.yaml

user:
  enabled: true    # Deploy user chart

dispatch:
  enabled: false   # Skip dispatch chart
```

Then upgrade:
```bash
helm upgrade robot-shop ./robot-shop -n robot-shop
```

### 7. Override Values from Command Line

```bash
# Override user replicas
helm install robot-shop ./robot-shop \
  --namespace robot-shop \
  --set user.replicas=5 \
  --set web.hpa.maxReplicas=20
```

### 8. Use Different Values Files

```bash
# Install with production values
helm install robot-shop ./robot-shop \
  --namespace robot-shop \
  --values robot-shop/values.yaml \
  --values values-prod.yaml
```

---

## Conditional Subchart Deployment

### In Chart.yaml

```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: user
    condition: user.enabled
  - name: web
    condition: web.enabled
  - name: mysql
    condition: mysql.enabled
```

### In values.yaml

```yaml
# robot-shop/values.yaml

user:
  enabled: true    # Will be deployed

web:
  enabled: true    # Will be deployed

mysql:
  enabled: false   # Will be skipped
```

---

## Complete Umbrella Chart Example

### robot-shop/Chart.yaml

```yaml
apiVersion: v2
name: robot-shop
description: A complete microservices e-commerce application
type: application
version: 1.0.0
appVersion: "2.1.0"

keywords:
  - microservices
  - e-commerce
  - demo
  - nodejs
  - java
  - python
  - go
  - php

home: https://github.com/instana/robot-shop
sources:
  - https://github.com/instana/robot-shop

maintainers:
  - name: DevOps Team
    email: devops@example.com

# Optional: If pulling charts from remote repos
# dependencies:
#   - name: redis
#     version: "17.x.x"
#     repository: "https://charts.bitnami.com/bitnami"
#     condition: redis.enabled
#   - name: prometheus
#     version: "15.x.x"
#     repository: "https://prometheus-community.github.io/helm-charts"
#     condition: prometheus.enabled
```

### robot-shop/templates/NOTES.txt

```
Thank you for installing {{ .Chart.Name }}!

Your release is named {{ .Release.Name }}.

To learn more about the release, try:

  $ helm status {{ .Release.Name }} -n {{ .Release.Namespace }}
  $ helm get all {{ .Release.Name }} -n {{ .Release.Namespace }}

The following services have been deployed:

{{- if .Values.web.enabled }}
- Web (Frontend): http://{{ .Values.web.ingress.host }}
{{- end }}

{{- if .Values.user.enabled }}
- User Service: {{ .Values.user.name }}:{{ .Values.user.service.port }}
{{- end }}

{{- if .Values.catalogue.enabled }}
- Catalogue Service: {{ .Values.catalogue.name }}:{{ .Values.catalogue.service.port }}
{{- end }}

Database Services:
{{- if .Values.mongodb.enabled }}
- MongoDB: {{ .Values.mongodb.name }}:{{ .Values.mongodb.port }}
{{- end }}
{{- if .Values.mysql.enabled }}
- MySQL: {{ .Values.mysql.name }}:{{ .Values.mysql.port }}
{{- end }}
{{- if .Values.redis.enabled }}
- Redis: {{ .Values.redis.name }}:{{ .Values.redis.port }}
{{- end }}

To access the application:
  kubectl port-forward -n {{ .Release.Namespace }} svc/web 8080:8080
  
Then visit: http://localhost:8080
```

---

## Troubleshooting

### Issue: Subchart not deploying

**Check:**
```bash
# Verify subchart is in charts/ directory
ls robot-shop/charts/

# Check if enabled in values
helm get values robot-shop -n robot-shop | grep -A 5 "user:"
```

### Issue: Values not being overridden

**Debug:**
```bash
# See computed values for user subchart
helm get values robot-shop -n robot-shop -o yaml | yq '.user'

# Template to see final YAML
helm template robot-shop ./robot-shop --show-only charts/user/templates/deployment.yaml
```

### Issue: Dependency update needed

```bash
# If using dependencies in Chart.yaml
helm dependency update robot-shop/
helm dependency list robot-shop/
```

---

## Summary

### Key Points

1. **Umbrella chart** = one chart that deploys multiple subcharts
2. **Subcharts** live in `robot-shop/charts/` directory
3. **Values hierarchy**: 
   - Command line (`--set`) > 
   - External file (`-f values-prod.yaml`) > 
   - Umbrella values.yaml > 
   - Subchart values.yaml > 
   - Template defaults
4. **Global values** are accessible to all subcharts via `.Values.global`
5. **Enable/disable** subcharts with `enabled: true/false`
6. **One command** deploys entire application

### Next Steps

1. Read `MULTI-ENVIRONMENT-VALUES-GUIDE.md` for dev/prod values
2. Read `EXTERNAL-CHARTS-GUIDE.md` for adding Redis, Prometheus
3. Create robot-shop/values.yaml with all your services
4. Test with `helm template` first
5. Deploy with `helm install`
