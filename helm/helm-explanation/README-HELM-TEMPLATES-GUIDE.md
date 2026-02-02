# Helm Templates Deep Dive Guide
## Understanding Kubernetes Manifests Line-by-Line with Helm

This guide explains Helm template syntax in detail, showing you how to convert static Kubernetes YAML into dynamic, reusable Helm templates.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Understanding the Problem](#understanding-the-problem)
3. [Helm Template Basics](#helm-template-basics)
4. [Kubernetes Manifest Types](#kubernetes-manifest-types)
   - [Deployment](#1-deployment)
   - [StatefulSet](#2-statefulset)
   - [Service](#3-service)
   - [ConfigMap](#4-configmap)
   - [Secret](#5-secret)
   - [Ingress](#6-ingress)
   - [HorizontalPodAutoscaler (HPA)](#7-horizontalpodautoscaler-hpa)
   - [NetworkPolicy](#8-networkpolicy)
   - [PersistentVolumeClaim (PVC)](#9-persistentvolumeclaim-pvc)
5. [HYBRID ENVIRONMENT VARIABLES](#hybrid-environment-variables)
6. [Creating Common Templates](#creating-common-templates)
7. [Service-Specific Templates](#service-specific-templates)
8. [Advanced Patterns](#advanced-patterns)
9. [Commands and Workflow](#commands-and-workflow)
10. [Debugging](#debugging)

---

## Introduction

When working with Kubernetes, you write YAML manifests to define resources. However, hardcoding values makes these manifests inflexible. **Helm** solves this by:

1. **Templating**: Replace hardcoded values with variables
2. **Reusability**: One template for multiple services
3. **Configuration Management**: Different values for dev/staging/prod
4. **Version Control**: Track changes to your infrastructure

This guide shows you **exactly** how to convert static YAML into Helm templates, line by line.

---

## Understanding the Problem

### Static YAML (Bad)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue
  namespace: robot-shop
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
        image: robotshop/catalogue:v1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: mongodb
```

**Problems:**
- Service name hardcoded (`catalogue`)
- Namespace hardcoded (`robot-shop`)
- Image hardcoded (`robotshop/catalogue:v1.0.0`)
- Replica count hardcoded (`2`)
- Port hardcoded (`8080`)
- Environment variables hardcoded

**To create another service**, you'd copy-paste and manually change 10+ values. Error-prone!

### Helm Template (Good)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Values.namespace }}
spec:
  replicas: {{ .Values.replicas }}
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
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
        ports:
        - containerPort: {{ .Values.port }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
```

**Benefits:**
- All values come from `values.yaml`
- One template = unlimited services
- Easy to override for different environments
- Type-safe and validated

---

## Helm Template Basics

### Core Syntax

#### 1. **Variable Interpolation**

```yaml
{{ .Values.name }}
```

- `{{` and `}}` = delimiters (mark start/end of template expression)
- `.Values` = root object containing all values from `values.yaml`
- `.Values.name` = access the `name` field

#### 2. **Nested Values**

```yaml
{{ .Values.image.repository }}
```

Access nested values using dot notation.

**values.yaml:**
```yaml
image:
  repository: robotshop
  name: catalogue
  version: v1.0.0
```

**Template:**
```yaml
image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
```

**Result:**
```yaml
image: robotshop/catalogue:v1.0.0
```

#### 3. **Whitespace Control**

```yaml
{{- .Values.name }}    # Remove whitespace before
{{ .Values.name -}}    # Remove whitespace after
{{- .Values.name -}}   # Remove whitespace both sides
```

**Critical for loops** to avoid extra blank lines.

#### 4. **Conditionals**

```yaml
{{- if .Values.enabled }}
replicas: {{ .Values.replicas }}
{{- else }}
replicas: 0
{{- end }}
```

#### 5. **Loops**

```yaml
{{- range $key, $value := .Values.env }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
```

#### 6. **Functions/Filters**

```yaml
{{ .Values.name | quote }}          # Add quotes
{{ .Values.name | upper }}          # Uppercase
{{ .Values.name | default "app" }}  # Default value
```

---

## Kubernetes Manifest Types

Let's convert each Kubernetes resource type to Helm templates.

---

### 1. Deployment

**Purpose:** Runs stateless applications with replicas, rolling updates, and health checks.

**Use for:** Web services, APIs, worker processes (catalogue, payment, user, ratings)

#### Static YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue
  namespace: robot-shop
  labels:
    app: catalogue
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalogue
  template:
    metadata:
      labels:
        app: catalogue
        tier: backend
    spec:
      containers:
      - name: catalogue
        image: robotshop/catalogue:v1.0.0
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: DB_HOST
          value: mongodb
        - name: DB_PORT
          value: "27017"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

#### Helm Template (deployment.yaml)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier }}
    spec:
      containers:
      - name: {{ .Values.name }}
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
        ports:
        - containerPort: {{ .Values.port }}
          name: http
        {{- if .Values.env }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
        {{- if .Values.livenessProbe }}
        livenessProbe:
          {{- toYaml .Values.livenessProbe | nindent 10 }}
        {{- end }}
        {{- if .Values.readinessProbe }}
        readinessProbe:
          {{- toYaml .Values.readinessProbe | nindent 10 }}
        {{- end }}
```

#### Line-by-Line Explanation

```yaml
apiVersion: apps/v1
kind: Deployment
```
- **Static:** These never change for Deployments
- API version for Deployment resources

```yaml
metadata:
  name: {{ .Values.name }}
```
- **Dynamic:** Service name from values.yaml
- `{{ .Values.name }}` → `catalogue`, `payment`, etc.

```yaml
  namespace: {{ .Release.Namespace }}
```
- **Built-in:** `.Release.Namespace` = namespace where Helm is installing
- Set via `helm install --namespace robot-shop`

```yaml
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier }}
```
- **Labels:** Metadata for organization/selection
- `tier` = `frontend`, `backend`, `database`

```yaml
spec:
  replicas: {{ .Values.replicas | default 1 }}
```
- **Replicas:** Number of pod copies
- `| default 1` → if not specified, use 1

```yaml
  selector:
    matchLabels:
      app: {{ .Values.name }}
```
- **Selector:** How Deployment finds its pods
- Must match `template.metadata.labels`

```yaml
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
```
- **Pod template:** Blueprint for pods
- Labels must match selector above

```yaml
      containers:
      - name: {{ .Values.name }}
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
```
- **Image:** Full Docker image path
- Example: `robotshop/catalogue:v1.0.0`

```yaml
        ports:
        - containerPort: {{ .Values.port }}
          name: http
```
- **Port:** Container listens on this port
- `name: http` = human-readable name

```yaml
        {{- if .Values.env }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
```
- **Environment Variables:**
  - `{{- if .Values.env }}` → only add env section if values exist
  - `{{- range $key, $value := .Values.env }}` → loop through env map
  - `{{ $value | quote }}` → add quotes (required for YAML strings)
  - `{{- end }}` → end loop
  - `{{- end }}` → end if

```yaml
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
```
- **Resources:** CPU/memory requests and limits
- `toYaml` → convert Go object to YAML
- `nindent 10` → indent 10 spaces

```yaml
        {{- if .Values.livenessProbe }}
        livenessProbe:
          {{- toYaml .Values.livenessProbe | nindent 10 }}
        {{- end }}
```
- **Liveness Probe:** Is container alive?
- Kubernetes restarts pod if fails
- `toYaml` → copy entire probe config from values

```yaml
        {{- if .Values.readinessProbe }}
        readinessProbe:
          {{- toYaml .Values.readinessProbe | nindent 10 }}
        {{- end }}
```
- **Readiness Probe:** Is container ready for traffic?
- Kubernetes removes from Service if fails
- Traffic only goes to ready pods

#### values.yaml for Deployment

```yaml
name: catalogue
tier: backend

image:
  repository: robotshop
  name: catalogue
  version: v1.0.0

replicas: 2
port: 8080

env:
  DB_HOST: mongodb
  DB_PORT: "27017"
  LOG_LEVEL: info

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

### 2. StatefulSet

**Purpose:** Runs stateful applications with stable network IDs, persistent storage, and ordered deployment.

**Use for:** Databases (MongoDB, MySQL, Redis, RabbitMQ)

#### Why StatefulSet vs Deployment?

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Pod Names | Random (catalogue-7d8f-abc) | Stable (mongodb-0, mongodb-1) |
| Network Identity | Changes on restart | Stable DNS (mongodb-0.mongodb) |
| Storage | Ephemeral or shared PVC | Dedicated PVC per pod |
| Startup Order | Parallel | Sequential (0 → 1 → 2) |
| Use Case | Stateless apps | Databases, clusters |

#### Static YAML

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: robot-shop
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
        tier: database
    spec:
      containers:
      - name: mongodb
        image: mongo:4.4
        ports:
        - containerPort: 27017
          name: mongo
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          valueFrom:
            secretKeyRef:
              name: mongodb-secret
              key: username
        - name: MONGO_INITDB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mongodb-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /data/db
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

#### Helm Template (statefulset.yaml)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
spec:
  serviceName: {{ .Values.name }}
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier }}
    spec:
      containers:
      - name: {{ .Values.name }}
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
        ports:
        - containerPort: {{ .Values.port }}
          name: {{ .Values.portName | default "tcp" }}
        {{- if .Values.envFromSecrets }}
        env:
        {{- range .Values.envFromSecrets }}
        - name: {{ .name }}
          valueFrom:
            secretKeyRef:
              name: {{ .secretName }}
              key: {{ .secretKey }}
        {{- end }}
        {{- end }}
        {{- if .Values.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.volumeMounts | nindent 8 }}
        {{- end }}
  {{- if .Values.volumeClaimTemplates }}
  volumeClaimTemplates:
  {{- toYaml .Values.volumeClaimTemplates | nindent 2 }}
  {{- end }}
```

#### Key Differences from Deployment

```yaml
spec:
  serviceName: {{ .Values.name }}
```
- **serviceName:** Required for StatefulSet
- Creates DNS: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`
- Example: `mongodb-0.mongodb.robot-shop.svc.cluster.local`

```yaml
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```
- **volumeClaimTemplates:** Creates PVC per pod
- Each pod gets its own persistent disk
- PVCs survive pod deletion

#### values.yaml for StatefulSet

```yaml
name: mongodb
tier: database

image:
  repository: mongo
  name: mongo
  version: "4.4"

replicas: 1
port: 27017
portName: mongo

envFromSecrets:
  - name: MONGO_INITDB_ROOT_USERNAME
    secretName: mongodb-secret
    secretKey: username
  - name: MONGO_INITDB_ROOT_PASSWORD
    secretName: mongodb-secret
    secretKey: password

volumeMounts:
  - name: data
    mountPath: /data/db

volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

---

### 3. Service

**Purpose:** Provides stable network endpoint for pods. Load balances traffic across replicas.

**Use for:** Every application needs a Service

#### Types of Services

1. **ClusterIP** (default): Internal only, within cluster
2. **NodePort**: Exposes on each node's IP at a static port
3. **LoadBalancer**: Cloud load balancer (AWS ELB, GCP LB)
4. **Headless**: No load balancing, for StatefulSets (DNS per pod)

#### Static YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: catalogue
  namespace: robot-shop
  labels:
    app: catalogue
spec:
  type: ClusterIP
  selector:
    app: catalogue
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
```

#### Helm Template (service.yaml)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  {{- if eq .Values.service.type "ClusterIP" }}
  {{- if .Values.service.clusterIP }}
  clusterIP: {{ .Values.service.clusterIP }}
  {{- end }}
  {{- end }}
  selector:
    app: {{ .Values.name }}
  ports:
  - name: {{ .Values.service.portName | default "http" }}
    port: {{ .Values.service.port }}
    targetPort: {{ .Values.port }}
    protocol: {{ .Values.service.protocol | default "TCP" }}
    {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
    nodePort: {{ .Values.service.nodePort }}
    {{- end }}
```

#### Line-by-Line Explanation

```yaml
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
```
- **Type:** ClusterIP, NodePort, LoadBalancer, or Headless
- Default to ClusterIP if not specified

```yaml
  {{- if eq .Values.service.type "ClusterIP" }}
  {{- if .Values.service.clusterIP }}
  clusterIP: {{ .Values.service.clusterIP }}
  {{- end }}
  {{- end }}
```
- **Headless Service:** Set `clusterIP: None`
- Only add if explicitly set in values
- `eq` = equals comparison

```yaml
  selector:
    app: {{ .Values.name }}
```
- **Selector:** Routes traffic to pods with matching labels
- Must match pod labels in Deployment/StatefulSet

```yaml
  ports:
  - name: {{ .Values.service.portName | default "http" }}
    port: {{ .Values.service.port }}
    targetPort: {{ .Values.port }}
```
- **port:** Service port (what clients connect to)
- **targetPort:** Container port (where traffic goes)
- Example: Service port 80 → Container port 8080

```yaml
    {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
    nodePort: {{ .Values.service.nodePort }}
    {{- end }}
```
- **NodePort:** Only set if type is NodePort
- Must be in range 30000-32767
- `and` = logical AND

#### values.yaml for Service

```yaml
name: catalogue
port: 8080

service:
  type: ClusterIP
  port: 80
  portName: http
  protocol: TCP
  # For NodePort:
  # type: NodePort
  # nodePort: 30080
  # For Headless (StatefulSet):
  # clusterIP: None
```

---

### 4. ConfigMap

**Purpose:** Store non-sensitive configuration as key-value pairs or files.

**Use for:** App config, feature flags, environment-specific settings

#### Static YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: catalogue-config
  namespace: robot-shop
data:
  # Simple key-value
  LOG_LEVEL: "info"
  CACHE_TTL: "300"
  
  # File content
  app.properties: |
    server.port=8080
    spring.datasource.url=jdbc:mysql://mysql:3306/catalogue
    spring.jpa.hibernate.ddl-auto=update
```

#### Helm Template (configmap.yaml)

```yaml
{{- if .Values.configMap }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.name }}-config
  namespace: {{ .Release.Namespace }}
data:
  {{- range $key, $value := .Values.configMap }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
```

#### Using ConfigMap in Deployment

**Option 1: As Environment Variables**

```yaml
envFrom:
  - configMapRef:
      name: {{ .Values.name }}-config
```

**Option 2: As Volume (File)**

```yaml
volumes:
  - name: config
    configMap:
      name: {{ .Values.name }}-config
volumeMounts:
  - name: config
    mountPath: /etc/config
    readOnly: true
```

#### values.yaml for ConfigMap

```yaml
name: catalogue

configMap:
  LOG_LEVEL: "info"
  CACHE_TTL: "300"
  FEATURE_NEW_UI: "true"
```

---

### 5. Secret

**Purpose:** Store sensitive data (passwords, tokens, keys). Base64 encoded.

**Use for:** Database passwords, API keys, TLS certificates

#### Static YAML

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-secret
  namespace: robot-shop
type: Opaque
data:
  username: YWRtaW4=          # base64("admin")
  password: cGFzc3dvcmQxMjM=  # base64("password123")
```

#### Helm Template (secret.yaml)

```yaml
{{- if .Values.secrets }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.name }}-secret
  namespace: {{ .Release.Namespace }}
type: Opaque
data:
  {{- range $key, $value := .Values.secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
{{- end }}
```

#### Line-by-Line Explanation

```yaml
type: Opaque
```
- **Opaque:** Generic secret (default type)
- Other types: `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`

```yaml
data:
  {{- range $key, $value := .Values.secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
```
- **b64enc:** Base64 encode function
- Helm automatically encodes plain text from values.yaml
- Never commit real secrets to Git!

#### Using Secrets in Deployment

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .Values.name }}-secret
        key: password
```

#### values.yaml for Secret

**⚠️ WARNING: Never commit real secrets to Git!**

```yaml
name: mongodb

# DO NOT DO THIS IN PRODUCTION
secrets:
  username: admin
  password: password123

# INSTEAD: Create secrets manually or use Sealed Secrets
# kubectl create secret generic mongodb-secret \
#   --from-literal=username=admin \
#   --from-literal=password=RealSecurePassword123!
```

#### Best Practices

1. **Don't store secrets in values.yaml** for production
2. **Use external secret managers**: AWS Secrets Manager, HashiCorp Vault, Azure Key Vault
3. **Use Sealed Secrets**: Encrypt secrets for Git storage
4. **Create manually**: `kubectl create secret`
5. **Reference only**: Templates only reference secret names, never contain values

---

### 6. Ingress

**Purpose:** HTTP/HTTPS routing from outside cluster to services. Single entry point.

**Use for:** Exposing web applications with custom domains

#### Static YAML

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: robot-shop
  namespace: robot-shop
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  tls:
  - hosts:
    - robotshop.example.com
    secretName: robotshop-tls
  rules:
  - host: robotshop.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web
            port:
              number: 80
      - path: /api/catalogue
        pathType: Prefix
        backend:
          service:
            name: catalogue
            port:
              number: 80
```

#### Helm Template (ingress.yaml)

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  {{- if .Values.ingress.annotations }}
  annotations:
    {{- toYaml .Values.ingress.annotations | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.tls }}
  tls:
  {{- range .Values.ingress.tls }}
  - hosts:
    {{- range .hosts }}
    - {{ . }}
    {{- end }}
    secretName: {{ .secretName }}
  {{- end }}
  {{- end }}
  rules:
  {{- range .Values.ingress.rules }}
  - host: {{ .host }}
    http:
      paths:
      {{- range .paths }}
      - path: {{ .path }}
        pathType: {{ .pathType | default "Prefix" }}
        backend:
          service:
            name: {{ .serviceName }}
            port:
              number: {{ .servicePort }}
      {{- end }}
  {{- end }}
{{- end }}
```

#### values.yaml for Ingress

```yaml
name: robot-shop

ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  
  tls:
    - hosts:
        - robotshop.example.com
      secretName: robotshop-tls
  
  rules:
    - host: robotshop.example.com
      paths:
        - path: /
          pathType: Prefix
          serviceName: web
          servicePort: 80
        - path: /api/catalogue
          pathType: Prefix
          serviceName: catalogue
          servicePort: 80
```

---

### 7. HorizontalPodAutoscaler (HPA)

**Purpose:** Automatically scale pods based on CPU/memory usage or custom metrics.

**Use for:** Variable traffic applications (web, API)

#### Static YAML

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: catalogue-hpa
  namespace: robot-shop
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: catalogue
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

#### Helm Template (hpa.yaml)

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Values.name }}-hpa
  namespace: {{ .Release.Namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Values.name }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  {{- if .Values.autoscaling.targetCPU }}
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPU }}
  {{- end }}
  {{- if .Values.autoscaling.targetMemory }}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetMemory }}
  {{- end }}
{{- end }}
```

#### values.yaml for HPA

```yaml
name: catalogue

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 70
  targetMemory: 80
```

---

### 8. NetworkPolicy

**Purpose:** Firewall rules for pods. Control ingress/egress traffic.

**Use for:** Security, isolate tiers (frontend can't access database directly)

#### Static YAML

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: catalogue-policy
  namespace: robot-shop
spec:
  podSelector:
    matchLabels:
      app: catalogue
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
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
```

#### Helm Template (networkpolicy.yaml)

```yaml
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Values.name }}-policy
  namespace: {{ .Release.Namespace }}
spec:
  podSelector:
    matchLabels:
      app: {{ .Values.name }}
  policyTypes:
  {{- toYaml .Values.networkPolicy.policyTypes | nindent 2 }}
  {{- if .Values.networkPolicy.ingress }}
  ingress:
  {{- toYaml .Values.networkPolicy.ingress | nindent 2 }}
  {{- end }}
  {{- if .Values.networkPolicy.egress }}
  egress:
  {{- toYaml .Values.networkPolicy.egress | nindent 2 }}
  {{- end }}
{{- end }}
```

#### values.yaml for NetworkPolicy

```yaml
name: catalogue

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  
  ingress:
    - from:
      - podSelector:
          matchLabels:
            tier: frontend
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
    # DNS access
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53
```

---

### 9. PersistentVolumeClaim (PVC)

**Purpose:** Request storage from cluster. Decouples storage from pods.

**Use for:** Databases, file uploads, shared storage

#### Static YAML

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data
  namespace: robot-shop
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard
```

#### Helm Template (pvc.yaml)

```yaml
{{- if and .Values.persistence.enabled (not .Values.persistence.existingClaim) }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.name }}-data
  namespace: {{ .Release.Namespace }}
spec:
  accessModes:
    {{- toYaml .Values.persistence.accessModes | nindent 4 }}
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
  {{- if .Values.persistence.storageClass }}
  storageClassName: {{ .Values.persistence.storageClass }}
  {{- end }}
{{- end }}
```

#### values.yaml for PVC

```yaml
name: mongodb

persistence:
  enabled: true
  size: 10Gi
  accessModes:
    - ReadWriteOnce
  storageClass: standard
  # Or use existing PVC:
  # existingClaim: mongodb-data-pvc
```

---

## HYBRID ENVIRONMENT VARIABLES

### The Problem This Solves

When deploying applications, you need **two types of configuration**:

1. **Non-Sensitive Config** (plain environment variables)
   - Database hosts, ports
   - API endpoints
   - Log levels
   - Feature flags
   - **Safe to store in Git**

2. **Sensitive Secrets** (secret references)
   - Database passwords
   - API keys
   - OAuth tokens
   - Encryption keys
   - **NEVER store in Git**

**The Challenge:** Most examples show either all-plain OR all-secret approaches. In reality, you need **BOTH in the same deployment**.

---

### Solution: Hybrid Environment Variables Pattern

This pattern lets you:
- ✅ Commit plain config to Git (values.yaml)
- ✅ Reference secrets created outside Helm (Kubernetes Secrets)
- ✅ Both appear as environment variables in the same container
- ✅ Clear separation of concerns
- ✅ Production-ready security

---

### Template Implementation

#### Complete Deployment Template with Hybrid Env

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier }}
    spec:
      containers:
      - name: {{ .Values.name }}
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
        ports:
        - containerPort: {{ .Values.port }}
          name: http
        
        {{- if or .Values.env .Values.envFromSecrets }}
        env:
        {{- if .Values.env }}
        # Plain environment variables (from values.yaml - safe for Git)
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        
        {{- if .Values.envFromSecrets }}
        # Secret references (Kubernetes Secrets - created outside Helm)
        {{- range .Values.envFromSecrets }}
        - name: {{ .name }}
          valueFrom:
            secretKeyRef:
              name: {{ .secretName }}
              key: {{ .secretKey }}
        {{- end }}
        {{- end }}
        {{- end }}
        
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
        
        {{- if .Values.livenessProbe }}
        livenessProbe:
          {{- toYaml .Values.livenessProbe | nindent 10 }}
        {{- end }}
        
        {{- if .Values.readinessProbe }}
        readinessProbe:
          {{- toYaml .Values.readinessProbe | nindent 10 }}
        {{- end }}
```

---

### Line-by-Line Explanation

#### 1. Check if ANY Environment Variables Exist

```yaml
{{- if or .Values.env .Values.envFromSecrets }}
env:
```

**Explanation:**
- `or` = logical OR operator
- Only add `env:` section if EITHER:
  - `.Values.env` exists (plain variables), OR
  - `.Values.envFromSecrets` exists (secret references)
- Prevents empty `env:` block

---

#### 2. Plain Environment Variables Section

```yaml
{{- if .Values.env }}
# Plain environment variables (from values.yaml - safe for Git)
{{- range $key, $value := .Values.env }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
```

**Explanation:**
- **`{{- if .Values.env }}`**: Only process if `env:` exists in values.yaml
- **`{{- range $key, $value := .Values.env }}`**: Loop through map
  - `$key` = environment variable name (e.g., `DB_HOST`)
  - `$value` = environment variable value (e.g., `mongodb`)
- **`{{ $value | quote }}`**: Add quotes around value
  - Ensures proper YAML string handling
  - Example: `LOG_LEVEL: info` becomes `LOG_LEVEL: "info"`
- **`{{- end }}`**: End loop
- **Comment**: Documents this section is for non-sensitive config

**What this generates:**
```yaml
env:
- name: DB_HOST
  value: "mongodb"
- name: DB_PORT
  value: "27017"
- name: LOG_LEVEL
  value: "info"
```

---

#### 3. Secret References Section

```yaml
{{- if .Values.envFromSecrets }}
# Secret references (Kubernetes Secrets - created outside Helm)
{{- range .Values.envFromSecrets }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .secretKey }}
{{- end }}
{{- end }}
```

**Explanation:**
- **`{{- if .Values.envFromSecrets }}`**: Only process if `envFromSecrets:` exists
- **`{{- range .Values.envFromSecrets }}`**: Loop through array of secret references
- Each secret reference has 3 fields:
  - **`.name`**: Environment variable name in container (e.g., `MYSQL_PASSWORD`)
  - **`.secretName`**: Kubernetes Secret resource name (e.g., `mysql-secrets`)
  - **`.secretKey`**: Key within the Secret (e.g., `password`)
- **`valueFrom:`**: Tells Kubernetes to get value from elsewhere (not inline)
- **`secretKeyRef:`**: Specifically references a Kubernetes Secret
- **Comment**: Documents this section is for sensitive data

**What this generates:**
```yaml
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: mysql-secrets
      key: password
- name: MYSQL_USER
  valueFrom:
    secretKeyRef:
      name: mysql-secrets
      key: username
```

---

#### 4. Close Environment Variables Section

```yaml
{{- end }}
```

**Explanation:**
- Closes the outer `{{- if or .Values.env .Values.envFromSecrets }}`
- Only added if we had at least one env type

---

### values.yaml Configuration

```yaml
name: shipping
tier: backend

image:
  repository: robotshop
  name: shipping
  version: v1.0.0

replicas: 2
port: 8080

# ========================================
# PLAIN ENVIRONMENT VARIABLES
# Safe to commit to Git
# ========================================
env:
  # Database connection (non-sensitive)
  DB_HOST: mysql
  DB_PORT: "3306"
  DB_NAME: shipping
  
  # Application config
  LOG_LEVEL: info
  APP_ENV: production
  
  # Feature flags
  ENABLE_METRICS: "true"
  ENABLE_TRACING: "true"

# ========================================
# SECRET REFERENCES
# NEVER commit actual secrets to Git
# Reference Kubernetes Secrets created separately
# ========================================
envFromSecrets:
  # Database credentials
  - name: MYSQL_USER
    secretName: mysql-secrets
    secretKey: username
  
  - name: MYSQL_PASSWORD
    secretName: mysql-secrets
    secretKey: password
  
  # External API credentials
  - name: STRIPE_API_KEY
    secretName: payment-secrets
    secretKey: stripe-api-key

resources:
  requests:
    cpu: "200m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

### What Kubernetes Generates (Final Pod Spec)

When you deploy with Helm, Kubernetes creates a pod with **both types** of environment variables:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shipping-7d9f8b5c4-xj2k9
  labels:
    app: shipping
    tier: backend
spec:
  containers:
  - name: shipping
    image: robotshop/shipping:v1.0.0
    ports:
    - containerPort: 8080
      name: http
    
    env:
    # Plain variables (from values.yaml)
    - name: DB_HOST
      value: "mysql"
    - name: DB_PORT
      value: "3306"
    - name: DB_NAME
      value: "shipping"
    - name: LOG_LEVEL
      value: "info"
    - name: APP_ENV
      value: "production"
    - name: ENABLE_METRICS
      value: "true"
    - name: ENABLE_TRACING
      value: "true"
    
    # Secret references (values injected at runtime by Kubernetes)
    - name: MYSQL_USER
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: username
    - name: MYSQL_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mysql-secrets
          key: password
    - name: STRIPE_API_KEY
      valueFrom:
        secretKeyRef:
          name: payment-secrets
          key: stripe-api-key
```

**Inside the container:**
```bash
$ env | sort
APP_ENV=production
DB_HOST=mysql
DB_PORT=3306
DB_NAME=shipping
ENABLE_METRICS=true
ENABLE_TRACING=true
LOG_LEVEL=info
MYSQL_PASSWORD=SecurePassword123!    # Injected from Secret
MYSQL_USER=root                       # Injected from Secret
STRIPE_API_KEY=sk_live_abc123xyz      # Injected from Secret
```

---

### Creating the Kubernetes Secrets

**Before deploying**, create secrets using one of these methods:

#### Method 1: kubectl create secret (Manual)

```bash
# MySQL credentials
kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=SecurePassword123! \
  --namespace robot-shop

# Payment credentials
kubectl create secret generic payment-secrets \
  --from-literal=stripe-api-key=sk_live_abc123xyz \
  --namespace robot-shop

# Verify
kubectl get secrets -n robot-shop
kubectl describe secret mysql-secrets -n robot-shop
```

#### Method 2: From files

```bash
# Create files with secrets
echo -n 'root' > username.txt
echo -n 'SecurePassword123!' > password.txt

# Create secret from files
kubectl create secret generic mysql-secrets \
  --from-file=username=username.txt \
  --from-file=password=password.txt \
  --namespace robot-shop

# Clean up files (NEVER commit to Git!)
rm username.txt password.txt
```

#### Method 3: Sealed Secrets (Encrypted for Git)

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Create normal secret (don't apply yet)
kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=SecurePassword123! \
  --dry-run=client -o yaml > mysql-secret.yaml

# Encrypt it
kubeseal -f mysql-secret.yaml -w mysql-sealed-secret.yaml

# NOW safe to commit to Git
git add mysql-sealed-secret.yaml
git commit -m "Add sealed MySQL credentials"

# Apply sealed secret
kubectl apply -f mysql-sealed-secret.yaml -n robot-shop
# Controller automatically decrypts and creates mysql-secrets Secret
```

#### Method 4: External Secret Manager (Production)

```bash
# Using AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-secrets
  namespace: robot-shop
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: mysql-secrets
  data:
    - secretKey: username
      remoteRef:
        key: prod/robot-shop/mysql
        property: username
    - secretKey: password
      remoteRef:
        key: prod/robot-shop/mysql
        property: password
```

---

### Real Service Examples

#### Example 1: Java/Spring Boot Service (Shipping)

```yaml
name: shipping
tier: backend

image:
  repository: robotshop
  name: shipping
  version: v1.0.0

replicas: 2
port: 8080

env:
  # Spring Boot Config
  SPRING_PROFILES_ACTIVE: production
  SERVER_PORT: "8080"
  
  # Database Config (non-sensitive)
  DB_HOST: mysql
  DB_PORT: "3306"
  DB_NAME: shipping
  
  # Connection Pool
  DB_POOL_SIZE: "10"
  DB_CONNECTION_TIMEOUT: "30000"
  
  # Logging
  LOG_LEVEL: info
  LOG_FORMAT: json

envFromSecrets:
  - name: DB_USERNAME
    secretName: mysql-secrets
    secretKey: username
  
  - name: DB_PASSWORD
    secretName: mysql-secrets
    secretKey: password

resources:
  requests:
    cpu: "200m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"
```

#### Example 2: Python/Flask Service (Payment)

```yaml
name: payment
tier: backend

image:
  repository: robotshop
  name: payment
  version: v1.0.0

replicas: 2
port: 8080

env:
  # Flask Config
  FLASK_ENV: production
  FLASK_DEBUG: "0"
  
  # RabbitMQ Config (non-sensitive)
  RABBITMQ_HOST: rabbitmq
  RABBITMQ_PORT: "5672"
  RABBITMQ_QUEUE: payment_queue
  
  # Payment Provider
  PAYMENT_PROVIDER: stripe
  PAYMENT_CURRENCY: USD

envFromSecrets:
  - name: RABBITMQ_USER
    secretName: rabbitmq-secrets
    secretKey: username
  
  - name: RABBITMQ_PASSWORD
    secretName: rabbitmq-secrets
    secretKey: password
  
  - name: STRIPE_SECRET_KEY
    secretName: payment-secrets
    secretKey: stripe-secret-key
  
  - name: STRIPE_PUBLISHABLE_KEY
    secretName: payment-secrets
    secretKey: stripe-publishable-key

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

#### Example 3: Node.js Service (User)

```yaml
name: user
tier: backend

image:
  repository: robotshop
  name: user
  version: v1.0.0

replicas: 3
port: 8080

env:
  # Node Config
  NODE_ENV: production
  PORT: "8080"
  
  # MongoDB Config (non-sensitive)
  MONGO_HOST: mongodb
  MONGO_PORT: "27017"
  MONGO_DB: users
  
  # Redis Config (non-sensitive)
  REDIS_HOST: redis
  REDIS_PORT: "6379"
  REDIS_DB: "0"
  
  # Session Config
  SESSION_TIMEOUT: "3600"
  SESSION_NAME: robot_session

envFromSecrets:
  - name: MONGO_USER
    secretName: mongodb-secrets
    secretKey: username
  
  - name: MONGO_PASSWORD
    secretName: mongodb-secrets
    secretKey: password
  
  - name: REDIS_PASSWORD
    secretName: redis-secrets
    secretKey: password
  
  - name: SESSION_SECRET
    secretName: user-secrets
    secretKey: session-secret
  
  - name: JWT_SECRET
    secretName: user-secrets
    secretKey: jwt-secret

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

### Security Best Practices

#### ✅ DO

1. **Separate plain config from secrets**
   ```yaml
   env:              # Plain config in values.yaml
   envFromSecrets:   # Secret references only
   ```

2. **Use descriptive secret names**
   ```yaml
   envFromSecrets:
     - name: DATABASE_PASSWORD    # Clear what it is
       secretName: mysql-secrets  # Clear which secret
       secretKey: password        # Clear which key
   ```

3. **Create secrets before deployment**
   ```bash
   kubectl create secret generic mysql-secrets ...
   helm install shipping ./shipping
   ```

4. **Use RBAC to protect secrets**
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: secret-reader
     namespace: robot-shop
   rules:
   - apiGroups: [""]
     resources: ["secrets"]
     resourceNames: ["mysql-secrets"]
     verbs: ["get"]
   ```

5. **Rotate secrets regularly**
   ```bash
   # Update secret
   kubectl create secret generic mysql-secrets \
     --from-literal=password=NewPassword456! \
     --dry-run=client -o yaml | kubectl apply -f -
   
   # Restart pods to pick up new secret
   kubectl rollout restart deployment/shipping -n robot-shop
   ```

6. **Use external secret managers in production**
   - AWS Secrets Manager
   - HashiCorp Vault
   - Azure Key Vault
   - Google Secret Manager

#### ❌ DON'T

1. **Never commit secrets to Git**
   ```yaml
   # BAD - DO NOT DO THIS
   envFromSecrets:
     - name: DB_PASSWORD
       value: SecurePassword123!  # WRONG!
   ```

2. **Don't use plain env for secrets**
   ```yaml
   # BAD - secrets in plain env
   env:
     DB_PASSWORD: SecurePassword123!  # Visible in values.yaml
   ```

3. **Don't create secrets in Helm templates**
   ```yaml
   # BAD - secret in template
   apiVersion: v1
   kind: Secret
   data:
     password: {{ .Values.password | b64enc }}
   ```

4. **Don't store secrets in Helm values**
   ```yaml
   # BAD - values.yaml committed to Git
   secrets:
     password: SecurePassword123!
   ```

---

### Troubleshooting

#### Issue 1: Secret not found

```bash
# Error
Error: Secret "mysql-secrets" not found

# Fix: Create the secret first
kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=pass123 \
  --namespace robot-shop
```

#### Issue 2: Wrong secret key

```yaml
# Error in logs
Error: key "pass" not found in secret "mysql-secrets"

# Check secret keys
kubectl get secret mysql-secrets -n robot-shop -o jsonpath='{.data}'

# Fix: Use correct key name
envFromSecrets:
  - name: MYSQL_PASSWORD
    secretName: mysql-secrets
    secretKey: password  # Must match actual key in secret
```

#### Issue 3: Secret in wrong namespace

```bash
# Error
Error: Secret "mysql-secrets" not found in namespace "default"

# Fix: Create in correct namespace
kubectl create secret generic mysql-secrets \
  --from-literal=password=pass123 \
  --namespace robot-shop  # Match deployment namespace
```

#### Issue 4: Empty environment variable

```bash
# Inside container
$ echo $MYSQL_PASSWORD
# (empty)

# Debug: Check if secret exists and has data
kubectl get secret mysql-secrets -n robot-shop -o yaml

# Check pod for secret reference
kubectl get pod shipping-xxx -n robot-shop -o yaml | grep -A 5 "env:"
```

---

### Complete Example: Deploying with Hybrid Env

```bash
# 1. Create namespace
kubectl create namespace robot-shop

# 2. Create secrets (BEFORE Helm install)
kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=SecurePassword123! \
  --namespace robot-shop

kubectl create secret generic payment-secrets \
  --from-literal=stripe-api-key=sk_live_abc123xyz \
  --namespace robot-shop

# 3. Verify secrets
kubectl get secrets -n robot-shop

# 4. Install Helm chart (references secrets)
helm install shipping ./shipping \
  --namespace robot-shop \
  --values values.yaml

# 5. Check deployment
kubectl get pods -n robot-shop
kubectl logs shipping-xxx -n robot-shop

# 6. Verify environment variables in container
kubectl exec -it shipping-xxx -n robot-shop -- env | sort
# Should show both plain vars and secret values

# 7. Update plain config (Git workflow)
# Edit values.yaml
vim values.yaml  # Change LOG_LEVEL: debug

git add values.yaml
git commit -m "Increase log level for debugging"
git push

helm upgrade shipping ./shipping \
  --namespace robot-shop \
  --values values.yaml

# 8. Update secrets (separate workflow - NO Git)
kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=NewPassword456! \
  --namespace robot-shop \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/shipping -n robot-shop
```

---

### Summary: Hybrid Pattern Benefits

| Aspect | Plain Env | Secret Env | Hybrid Pattern |
|--------|-----------|------------|----------------|
| **Storage** | values.yaml (Git) | Kubernetes Secrets | Both |
| **Security** | Low (visible in Git) | High (encrypted at rest) | High for secrets, Git for config |
| **Flexibility** | Easy to change | Requires kubectl | Both easy |
| **Version Control** | Yes (Git) | No (outside Git) | Config in Git, secrets separate |
| **Use Cases** | DB hosts, ports, flags | Passwords, keys, tokens | All configuration needs |
| **Production Ready** | No (for sensitive data) | Yes | ✅ Yes |

**Key Takeaway:** Use `env:` for public config (commit to Git) and `envFromSecrets:` for sensitive data (Kubernetes Secrets). Both appear as environment variables in your container.

---

## Creating Common Templates

Now let's create **reusable templates** that work for multiple services.

### Directory Structure

```
charts/
  _common/
    templates/
      _deployment.yaml
      _service.yaml
      _helpers.tpl
  catalogue/
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml    # Uses _common/_deployment.yaml
      service.yaml       # Uses _common/_service.yaml
  payment/
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
```

### Creating _deployment.yaml (Common Template)

`charts/_common/templates/_deployment.yaml`:

```yaml
{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier }}
    {{- if .Values.labels }}
    {{- toYaml .Values.labels | nindent 4 }}
    {{- end }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier }}
        {{- if .Values.podLabels }}
        {{- toYaml .Values.podLabels | nindent 8 }}
        {{- end }}
    spec:
      {{- if .Values.serviceAccountName }}
      serviceAccountName: {{ .Values.serviceAccountName }}
      {{- end }}
      
      {{- if .Values.initContainers }}
      initContainers:
      {{- toYaml .Values.initContainers | nindent 6 }}
      {{- end }}
      
      containers:
      - name: {{ .Values.name }}
        image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        
        ports:
        - containerPort: {{ .Values.port }}
          name: http
          protocol: TCP
        
        {{- if or .Values.env .Values.envFrom .Values.envFromSecrets }}
        env:
        {{- if .Values.env }}
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        
        {{- if .Values.envFromSecrets }}
        {{- range .Values.envFromSecrets }}
        - name: {{ .name }}
          valueFrom:
            secretKeyRef:
              name: {{ .secretName }}
              key: {{ .secretKey }}
        {{- end }}
        {{- end }}
        {{- end }}
        
        {{- if .Values.envFrom }}
        envFrom:
        {{- toYaml .Values.envFrom | nindent 8 }}
        {{- end }}
        
        {{- if .Values.volumeMounts }}
        volumeMounts:
        {{- toYaml .Values.volumeMounts | nindent 8 }}
        {{- end }}
        
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
        
        {{- if .Values.livenessProbe }}
        livenessProbe:
          {{- toYaml .Values.livenessProbe | nindent 10 }}
        {{- end }}
        
        {{- if .Values.readinessProbe }}
        readinessProbe:
          {{- toYaml .Values.readinessProbe | nindent 10 }}
        {{- end }}
        
        {{- if .Values.startupProbe }}
        startupProbe:
          {{- toYaml .Values.startupProbe | nindent 10 }}
        {{- end }}
      
      {{- if .Values.volumes }}
      volumes:
      {{- toYaml .Values.volumes | nindent 6 }}
      {{- end }}
{{- end -}}
```

### Using Common Templates

In service-specific chart (`charts/catalogue/templates/deployment.yaml`):

```yaml
{{- include "common.deployment" . -}}
```

That's it! One line uses the entire common template.

---

## Service-Specific Templates

When services need unique configurations:

### Option 1: Override Values

```yaml
# catalogue/values.yaml
name: catalogue
tier: backend
replicas: 2

# Special config only for catalogue
podLabels:
  monitoring: prometheus
  backup: "true"

initContainers:
  - name: wait-for-db
    image: busybox:1.28
    command: ['sh', '-c', 'until nc -z mongodb 27017; do sleep 2; done']
```

### Option 2: Extend Template

```yaml
# catalogue/templates/deployment.yaml
{{- include "common.deployment" . -}}

---
# Add catalogue-specific resources
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.name }}-queries
data:
  queries.sql: |
    SELECT * FROM products WHERE category = 'robots';
```

---

## Advanced Patterns

### 1. Conditional Resources

```yaml
{{- if eq .Values.tier "database" }}
# Include StatefulSet
{{- include "common.statefulset" . }}
{{- else }}
# Include Deployment
{{- include "common.deployment" . }}
{{- end }}
```

### 2. Multiple Containers

```yaml
# values.yaml
name: web
containers:
  - name: nginx
    image: nginx:1.21
    port: 80
  - name: sidecar-logger
    image: fluent/fluentd:v1.14
    port: 24224
```

```yaml
# template
containers:
{{- range .Values.containers }}
- name: {{ .name }}
  image: {{ .image }}
  ports:
  - containerPort: {{ .port }}
{{- end }}
```

### 3. Environment-Specific Values

```yaml
# values-dev.yaml
replicas: 1
resources:
  requests:
    cpu: "50m"
    memory: "64Mi"

# values-prod.yaml
replicas: 5
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
```

```bash
# Deploy to dev
helm install catalogue ./catalogue -f values-dev.yaml

# Deploy to prod
helm install catalogue ./catalogue -f values-prod.yaml
```

---

## Commands and Workflow

### Development Workflow

```bash
# 1. Create chart
helm create myservice

# 2. Edit templates and values
vim myservice/templates/deployment.yaml
vim myservice/values.yaml

# 3. Validate syntax
helm lint myservice

# 4. Dry run (see what will be created)
helm install myservice ./myservice --dry-run --debug

# 5. Template (generate YAML without installing)
helm template myservice ./myservice

# 6. Install
helm install myservice ./myservice --namespace robot-shop

# 7. Check status
helm list -n robot-shop
kubectl get all -n robot-shop

# 8. Upgrade after changes
helm upgrade myservice ./myservice --namespace robot-shop

# 9. Rollback if needed
helm rollback myservice 1 --namespace robot-shop

# 10. Uninstall
helm uninstall myservice --namespace robot-shop
```

### Testing Templates

```bash
# See rendered templates
helm template myservice ./myservice --values values.yaml

# See templates with specific values
helm template myservice ./myservice --set replicas=3

# Debug template rendering
helm install myservice ./myservice --dry-run --debug
```

---

## Debugging

### Common Errors

#### 1. Template Syntax Error

```bash
Error: template: myservice/templates/deployment.yaml:15:20: 
  executing "myservice/templates/deployment.yaml" at <.Values.nam>: 
  can't evaluate field nam in type interface {}
```

**Fix:** Typo in variable name
```yaml
# Wrong
{{ .Values.nam }}

# Right
{{ .Values.name }}
```

#### 2. Missing Required Value

```bash
Error: template: myservice/templates/deployment.yaml:10:15: 
  executing "myservice/templates/deployment.yaml" at <.Values.image.version>: 
  nil pointer evaluating interface {}.version
```

**Fix:** Add default or check existence
```yaml
# Option 1: Default value
image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version | default "latest" }}

# Option 2: Conditional
{{- if .Values.image.version }}
image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
{{- end }}
```

#### 3. Indentation Error

```yaml
# Wrong (resources not indented correctly)
containers:
- name: app
  image: myapp:latest
resources:
  requests:
    cpu: "100m"
```

**Fix:** Use `nindent`
```yaml
containers:
- name: app
  image: myapp:latest
  {{- if .Values.resources }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  {{- end }}
```

### Debugging Commands

```bash
# Show all values (including defaults)
helm get values myservice --all

# Show computed values
helm get values myservice

# Show rendered templates
helm get manifest myservice

# Show full release info
helm get all myservice

# Verify template syntax
helm lint myservice/

# Test with different values
helm template myservice ./ --set replicas=10
```

---

## Summary

### Key Takeaways

1. **Helm templates = YAML + variables**
   - Replace hardcoded values with `{{ .Values.xxx }}`
   - Use conditionals (`if`), loops (`range`), and functions (`quote`, `toYaml`)

2. **Separation of concerns**
   - **Templates** (`.yaml` files): Structure (what resources)
   - **Values** (`values.yaml`): Configuration (specific values)
   - **Common templates**: Shared logic across services

3. **One template, many services**
   - Write once, reuse everywhere
   - Different values.yaml for each service
   - Environment-specific values (dev, staging, prod)

4. **Production patterns**
   - Use common templates for consistency
   - Separate config (Git) from secrets (Kubernetes Secrets)
   - Version control everything except secrets
   - Test with `helm template` and `--dry-run`

5. **Kubernetes resources covered**
   - Deployment (stateless apps)
   - StatefulSet (databases)
   - Service (networking)
   - ConfigMap (config files)
   - Secret (sensitive data)
   - Ingress (external access)
   - HPA (autoscaling)
   - NetworkPolicy (security)
   - PVC (storage)

### Next Steps

1. Create common templates (`_common/`)
2. Build service charts using common templates
3. Create umbrella chart with dependencies
4. Set up different values for environments
5. Implement GitOps with ArgoCD
6. Add monitoring and observability

---

This guide provides everything you need to convert static Kubernetes YAML into production-ready Helm templates. Each concept is explained line-by-line with real examples from the Robot-Shop microservices architecture.
