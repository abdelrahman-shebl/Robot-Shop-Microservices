# Complete Guide: Creating and Using Common Templates
## From Scratch - Structure, References, and Per-Service Customization

---

## Table of Contents

1. [The Problem This Solves](#the-problem-this-solves)
2. [Directory Structure](#directory-structure)
3. [How Common Templates Work](#how-common-templates-work)
4. [Creating Common Templates](#creating-common-templates)
5. [Creating Service Charts](#creating-service-charts)
6. [Referencing Common Templates](#referencing-common-templates)
7. [Per-Service Customization](#per-service-customization)
8. [All Resource Types (Deployment, StatefulSet, HPA, Ingress, NetworkPolicy)](#all-resource-types)
9. [Real Examples for All 7 Services](#real-examples-for-all-7-services)
10. [Commands and Workflow](#commands-and-workflow)

---

## The Problem This Solves

### Without Common Templates (Bad)

You have 7 services. Each needs similar Kubernetes resources:

```
charts/
  catalogue/
    templates/
      deployment.yaml      (120 lines) - 80% duplicated
      service.yaml         (50 lines)  - 90% duplicated
      hpa.yaml             (30 lines)  - duplicated logic
      networkpolicy.yaml   (40 lines)  - similar rules
  
  payment/
    templates/
      deployment.yaml      (120 lines) - SAME 80% as catalogue
      service.yaml         (50 lines)  - SAME 90% as catalogue
      hpa.yaml             (30 lines)  - SAME logic as catalogue
      networkpolicy.yaml   (40 lines)  - SAME rules as catalogue
  
  user/
    templates/
      deployment.yaml      (120 lines) - SAME 80% again
      ... (repeat for 4 more services)
```

**Problems:**
- 1,000+ lines of duplicated code
- Bug fix in one template = fix in 7 places
- Hard to keep patterns consistent
- Maintenance nightmare

### With Common Templates (Good)

```
charts/
  _common/
    templates/
      _deployment.yaml      (common logic)
      _statefulset.yaml     (common logic)
      _hpa.yaml             (common logic)
      _ingress.yaml         (common logic)
      _networkpolicy.yaml   (common logic)
      _service.yaml         (common logic)
      _helpers.tpl          (reusable functions)
  
  catalogue/
    templates/
      deployment.yaml       (1 line: {{ include "common.deployment" . }})
      hpa.yaml              (1 line: {{ include "common.hpa" . }})
      networkpolicy.yaml    (1 line: {{ include "common.networkpolicy" . }})
    values.yaml             (configuration specific to catalogue)
  
  payment/
    templates/
      deployment.yaml       (1 line: same include)
      hpa.yaml              (1 line: same include)
    values.yaml             (configuration specific to payment)
  
  ... (5 more services, same pattern)
```

**Benefits:**
- 100 lines total vs 1,000+
- Single source of truth for each resource type
- Bug fix in one place = fixed everywhere
- Easy to add new services
- Consistent patterns across all services

---

## Directory Structure

### Complete Project Layout

```
robot-shop/
helm/
  robot-shop/                          ← Umbrella chart (main)
    Chart.yaml
    values.yaml
    templates/
      NOTES.txt
  
  _common/                              ← Shared templates (NOT a chart)
    Chart.yaml                          ← Optional, metadata only
    templates/
      _deployment.yaml                  ← Common Deployment template
      _statefulset.yaml                 ← Common StatefulSet template
      _service.yaml                     ← Common Service template
      _hpa.yaml                         ← Common HPA template
      _ingress.yaml                     ← Common Ingress template
      _networkpolicy.yaml               ← Common NetworkPolicy template
      _configmap.yaml                   ← Common ConfigMap template
      _secret.yaml                      ← Common Secret template
      _helpers.tpl                      ← Helper functions
  
  catalogue/                            ← Service chart 1
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml                   ← References _common deployment
      service.yaml                      ← References _common service
      hpa.yaml                          ← References _common hpa
  
  payment/                              ← Service chart 2
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
      hpa.yaml
  
  user/                                 ← Service chart 3
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
      networkpolicy.yaml
  
  ratings/                              ← Service chart 4
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
  
  shipping/                             ← Service chart 5
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
      statefulset.yaml                  ← Some services have StatefulSet too
  
  cart/                                 ← Service chart 6
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
  
  dispatch/                             ← Service chart 7
    Chart.yaml
    values.yaml
    templates/
      deployment.yaml
      service.yaml
```

### Key Points

1. **`_common/`**: NOT a real chart
   - Contains template files starting with `_`
   - These are **templates/templates** (meta-templates)
   - Not deployed directly
   - Used by all service charts

2. **Service charts** (`catalogue/`, `payment/`, etc.): Real charts
   - Have `Chart.yaml` and `values.yaml`
   - Can be deployed individually
   - Each has own values for customization
   - Templates reference `_common/` templates

3. **Files starting with `_`**: Partial templates
   - `_deployment.yaml`: Not deployed as-is
   - `deployment.yaml`: In service chart, includes _common content

---

## How Common Templates Work

### The Include/Define Pattern

```yaml
# _common/templates/_deployment.yaml
{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
...
{{- end -}}
```

**Explanation:**
- `{{- define "common.deployment" -}}`: Create named template called `common.deployment`
- All YAML inside is the template content
- `{{- end -}}`: Close the definition

### How to Use It

```yaml
# catalogue/templates/deployment.yaml
{{- include "common.deployment" . -}}
```

**Explanation:**
- `include "common.deployment"`: Call the template named `common.deployment`
- `. ` : Pass current context (values, release info, etc.)
- Renders the full deployment using catalogue's values.yaml

### Data Flow

```
catalogue/values.yaml
       ↓
       ↓ (context passed via ".")
       ↓
catalogue/templates/deployment.yaml
       ↓
       ↓ ({{ include "common.deployment" . }})
       ↓
_common/templates/_deployment.yaml
       ↓
       ↓ (uses {{ .Values.xxx }} from catalogue/values.yaml)
       ↓
Generated Kubernetes YAML
(catalogue deployment with catalogue's values)
```

### Multiple Resources from One Template

You can include multiple resource types:

```yaml
# catalogue/templates/deployment.yaml
{{- include "common.deployment" . -}}

---
# catalogue/templates/service.yaml
{{- include "common.service" . -}}

---
# catalogue/templates/hpa.yaml
{{- include "common.hpa" . -}}

---
# catalogue/templates/networkpolicy.yaml
{{- include "common.networkpolicy" . -}}
```

Each file calls `include` to render that specific resource type.

---

## Creating Common Templates

### Step 1: Create _common Directory

```bash
mkdir -p /home/abdelrahman/Desktop/DevOps/robot-shop/helm/_common/templates
```

### Step 2: Create _deployment.yaml (Common Template)

File: `_common/templates/_deployment.yaml`

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
{{- end -}}
```

**Key Points:**
- `{{- define "common.deployment" -}}`: Names this template as `common.deployment`
- All variable references use `.Values.xxx`
- Conditional logic with `{{- if }}`
- Proper indentation with `nindent`
- `{{- end -}}`: Closes the definition

### Step 3: Create _service.yaml (Common Template)

File: `_common/templates/_service.yaml`

```yaml
{{- define "common.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  selector:
    app: {{ .Values.name }}
  ports:
  - name: http
    port: {{ .Values.service.port | default 80 }}
    targetPort: {{ .Values.port }}
    protocol: TCP
{{- end -}}
```

### Step 4: Create _hpa.yaml (Common Template)

File: `_common/templates/_hpa.yaml`

```yaml
{{- define "common.hpa" -}}
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
  minReplicas: {{ .Values.autoscaling.minReplicas | default 1 }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas | default 5 }}
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
{{- end -}}
```

**Key Point:**
- Entire HPA is wrapped in `{{- if .Values.autoscaling.enabled }}`
- Only creates HPA if enabled in values.yaml

### Step 5: Create _statefulset.yaml (Common Template)

File: `_common/templates/_statefulset.yaml`

```yaml
{{- define "common.statefulset" -}}
{{- if .Values.statefulSet.enabled }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier }}
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
          name: tcp
        
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
        
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
  
  {{- if .Values.volumeClaimTemplates }}
  volumeClaimTemplates:
  {{- toYaml .Values.volumeClaimTemplates | nindent 2 }}
  {{- end }}
{{- end }}
{{- end -}}
```

### Step 6: Create _ingress.yaml (Common Template)

File: `_common/templates/_ingress.yaml`

```yaml
{{- define "common.ingress" -}}
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
            name: {{ .serviceName | default $.Values.name }}
            port:
              number: {{ .servicePort | default $.Values.service.port | default 80 }}
      {{- end }}
  {{- end }}
{{- end }}
{{- end -}}
```

**Key Point:**
- `$.Values.name`: Access parent chart values (using `$`)
- Allows defaults if not specified

### Step 7: Create _networkpolicy.yaml (Common Template)

File: `_common/templates/_networkpolicy.yaml`

```yaml
{{- define "common.networkpolicy" -}}
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
{{- end -}}
```

---

## Creating Service Charts

### Step 1: Create Service Chart Directory

```bash
# Example: Create catalogue chart
mkdir -p /home/abdelrahman/Desktop/DevOps/robot-shop/helm/catalogue/templates
```

### Step 2: Create Chart.yaml

File: `catalogue/Chart.yaml`

```yaml
apiVersion: v2
name: catalogue
description: A Helm chart for Kubernetes
type: application
version: 0.1.0
appVersion: "1.0"
```

**What each field means:**
- `apiVersion: v2`: Helm 3 format
- `name`: Chart name (must match directory)
- `type: application`: This is an application (not a library)
- `version`: Chart version (increment when you change template)
- `appVersion`: Application version

### Step 3: Create values.yaml

File: `catalogue/values.yaml`

```yaml
# Service identification
name: catalogue
tier: backend

# Image configuration
image:
  repository: robotshop
  name: catalogue
  version: v1.0.0

# Deployment configuration
replicas: 2
port: 8080

# Service configuration
service:
  type: ClusterIP
  port: 80

# Environment variables (non-sensitive)
env:
  DB_HOST: mongodb
  DB_PORT: "27017"
  LOG_LEVEL: info

# Secret references (sensitive data)
envFromSecrets:
  - name: MONGODB_USER
    secretName: mongodb-secrets
    secretKey: username
  - name: MONGODB_PASSWORD
    secretName: mongodb-secrets
    secretKey: password

# Resource limits
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

# Health checks
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

# Autoscaling (HPA)
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 70
  targetMemory: 80

# Ingress
ingress:
  enabled: false
  annotations: {}
  tls: []
  rules: []

# Network Policy
networkPolicy:
  enabled: false
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress: []

# StatefulSet (usually not enabled for services)
statefulSet:
  enabled: false
```

---

## Referencing Common Templates

### Step 4: Create deployment.yaml (References _common)

File: `catalogue/templates/deployment.yaml`

```yaml
{{- include "common.deployment" . -}}
```

**That's it!** Just one line. Helm will:

1. Find `common.deployment` template
2. Pass current context (`.`)
3. Use `catalogue/values.yaml` for all variables
4. Render the full Deployment

### Step 5: Create service.yaml (References _common)

File: `catalogue/templates/service.yaml`

```yaml
{{- include "common.service" . -}}
```

### Step 6: Create hpa.yaml (References _common)

File: `catalogue/templates/hpa.yaml`

```yaml
{{- include "common.hpa" . -}}
```

### Complete Templates Directory

```
catalogue/templates/
  deployment.yaml     → {{ include "common.deployment" . }}
  service.yaml        → {{ include "common.service" . }}
  hpa.yaml            → {{ include "common.hpa" . }}
```

That's the entire chart! Each file is one line.

---

## Per-Service Customization

### The Key: Different values.yaml for Each Service

Each service chart has **its own values.yaml** with **its own configuration**.

### Example 1: Catalogue (Simple Service)

File: `catalogue/values.yaml`

```yaml
name: catalogue
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: catalogue
  version: v1.0.0

env:
  DB_HOST: mongodb
  DB_PORT: "27017"
  LOG_LEVEL: info

envFromSecrets:
  - name: MONGODB_USER
    secretName: mongodb-secrets
    secretKey: username
  - name: MONGODB_PASSWORD
    secretName: mongodb-secrets
    secretKey: password

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 70
```

### Example 2: Payment (More Resources)

File: `payment/values.yaml`

```yaml
name: payment
tier: backend
replicas: 3              # ← Different: More replicas
port: 8080

image:
  repository: robotshop
  name: payment
  version: v1.0.0

env:
  RABBITMQ_HOST: rabbitmq
  RABBITMQ_PORT: "5672"
  PAYMENT_PROVIDER: stripe    # ← Different: Payment-specific config
  LOG_LEVEL: debug             # ← Different: More logging for payment

envFromSecrets:
  - name: RABBITMQ_USER
    secretName: rabbitmq-secrets
    secretKey: username
  - name: RABBITMQ_PASSWORD
    secretName: rabbitmq-secrets
    secretKey: password
  - name: STRIPE_API_KEY      # ← Different: Payment-specific secrets
    secretName: payment-secrets
    secretKey: stripe-api-key

resources:
  requests:
    cpu: "200m"              # ← Different: Needs more CPU
    memory: "256Mi"          # ← Different: Needs more memory
  limits:
    cpu: "1000m"
    memory: "512Mi"

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10           # ← Different: Scales higher
  targetCPU: 60             # ← Different: More aggressive scaling
```

### Example 3: MongoDB (StatefulSet)

File: `mongodb/values.yaml`

```yaml
name: mongodb
tier: database
replicas: 1
port: 27017

image:
  repository: mongo
  name: mongo
  version: "5.0"

envFromSecrets:
  - name: MONGO_INITDB_ROOT_USERNAME
    secretName: mongodb-secrets
    secretKey: username
  - name: MONGO_INITDB_ROOT_PASSWORD
    secretName: mongodb-secrets
    secretKey: password

resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"

# StatefulSet configuration (different from Deployment)
statefulSet:
  enabled: true

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

# No autoscaling for databases
autoscaling:
  enabled: false
```

### How Helm Uses Them

```bash
# Deploy catalogue
helm install catalogue ./catalogue
# → Uses catalogue/values.yaml

# Deploy payment
helm install payment ./payment
# → Uses payment/values.yaml

# Deploy mongodb
helm install mongodb ./mongodb
# → Uses mongodb/values.yaml
```

Each chart has its **own values**, but uses the **same templates** from `_common/`.

---

## All Resource Types

### Complete Common Templates Directory Structure

```
_common/templates/
  _deployment.yaml          ← For stateless apps
  _statefulset.yaml         ← For stateful apps (databases)
  _service.yaml             ← All services need this
  _hpa.yaml                 ← Optional: Auto-scaling
  _ingress.yaml             ← Optional: External access
  _networkpolicy.yaml       ← Optional: Network security
  _configmap.yaml           ← Optional: Config files
  _secret.yaml              ← Optional: Sensitive data
```

### _configmap.yaml (Optional)

File: `_common/templates/_configmap.yaml`

```yaml
{{- define "common.configmap" -}}
{{- if .Values.configMap.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.name }}-config
  namespace: {{ .Release.Namespace }}
data:
  {{- range $key, $value := .Values.configMap.data }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
{{- end }}
{{- end -}}
```

### _secret.yaml (Optional)

File: `_common/templates/_secret.yaml`

```yaml
{{- define "common.secret" -}}
{{- if .Values.secrets.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.name }}-secret
  namespace: {{ .Release.Namespace }}
type: Opaque
data:
  {{- range $key, $value := .Values.secrets.data }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
{{- end }}
{{- end -}}
```

### How to Reference Additional Templates

Add to service chart templates:

```yaml
# catalogue/templates/configmap.yaml
{{- include "common.configmap" . -}}

# catalogue/templates/secret.yaml
{{- include "common.secret" . -}}

# catalogue/templates/networkpolicy.yaml
{{- include "common.networkpolicy" . -}}

# catalogue/templates/ingress.yaml
{{- include "common.ingress" . -}}
```

Then enable in values.yaml:

```yaml
configMap:
  enabled: true
  data:
    LOG_LEVEL: "info"
    CACHE_TTL: "300"

secrets:
  enabled: false  # Usually false - create secrets manually

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress: []

ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: nginx
  tls: []
  rules: []
```

---

## Real Examples for All 7 Services

### Service 1: Catalogue (Node.js, Simple)

#### Chart.yaml
```yaml
apiVersion: v2
name: catalogue
description: Product catalogue service
type: application
version: 0.1.0
appVersion: "1.0"
```

#### values.yaml
```yaml
name: catalogue
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: catalogue
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  DB_HOST: mongodb
  DB_PORT: "27017"
  LOG_LEVEL: info

envFromSecrets:
  - name: MONGODB_USER
    secretName: mongodb-secrets
    secretKey: username
  - name: MONGODB_PASSWORD
    secretName: mongodb-secrets
    secretKey: password

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

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 70

ingress:
  enabled: false

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
    # DNS
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

#### templates/
```
deployment.yaml:
{{- include "common.deployment" . -}}

service.yaml:
{{- include "common.service" . -}}

hpa.yaml:
{{- include "common.hpa" . -}}

networkpolicy.yaml:
{{- include "common.networkpolicy" . -}}
```

---

### Service 2: Payment (Python/Flask, More Complex)

#### Chart.yaml
```yaml
apiVersion: v2
name: payment
description: Payment processing service
type: application
version: 0.1.0
appVersion: "1.0"
```

#### values.yaml
```yaml
name: payment
tier: backend
replicas: 3
port: 8080

image:
  repository: robotshop
  name: payment
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  FLASK_ENV: production
  RABBITMQ_HOST: rabbitmq
  RABBITMQ_PORT: "5672"
  PAYMENT_PROVIDER: stripe
  LOG_LEVEL: info

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

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPU: 60
  targetMemory: 75

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
            app: rabbitmq
      ports:
      - protocol: TCP
        port: 5672
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Service 3: User (Node.js, Database + Cache)

#### values.yaml
```yaml
name: user
tier: backend
replicas: 3
port: 8080

image:
  repository: robotshop
  name: user
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  NODE_ENV: production
  MONGO_HOST: mongodb
  MONGO_PORT: "27017"
  MONGO_DB: users
  REDIS_HOST: redis
  REDIS_PORT: "6379"
  SESSION_TIMEOUT: "3600"
  LOG_LEVEL: info

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

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 8
  targetCPU: 70

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
    - to:
      - podSelector:
          matchLabels:
            app: redis
      ports:
      - protocol: TCP
        port: 6379
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Service 4: Ratings (PHP/Laravel, Database)

#### values.yaml
```yaml
name: ratings
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: ratings
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  APP_ENV: production
  MYSQL_HOST: mysql
  MYSQL_PORT: "3306"
  MYSQL_DATABASE: ratings
  LOG_LEVEL: info

envFromSecrets:
  - name: MYSQL_USER
    secretName: mysql-secrets
    secretKey: username
  - name: MYSQL_PASSWORD
    secretName: mysql-secrets
    secretKey: password
  - name: APP_KEY
    secretName: ratings-secrets
    secretKey: app-key

resources:
  requests:
    cpu: "150m"
    memory: "256Mi"
  limits:
    cpu: "750m"
    memory: "512Mi"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPU: 70

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
            app: mysql
      ports:
      - protocol: TCP
        port: 3306
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Service 5: Shipping (Java/Spring Boot, Database)

#### values.yaml
```yaml
name: shipping
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: shipping
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  SPRING_PROFILES_ACTIVE: production
  MYSQL_HOST: mysql
  MYSQL_PORT: "3306"
  MYSQL_DATABASE: shipping
  LOG_LEVEL: info

envFromSecrets:
  - name: MYSQL_USER
    secretName: mysql-secrets
    secretKey: username
  - name: MYSQL_PASSWORD
    secretName: mysql-secrets
    secretKey: password

resources:
  requests:
    cpu: "200m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 40
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 5

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 70

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
            app: mysql
      ports:
      - protocol: TCP
        port: 3306
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Service 6: Cart (Node.js, Simple + Redis)

#### values.yaml
```yaml
name: cart
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: cart
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  REDIS_HOST: redis
  REDIS_PORT: "6379"
  LOG_LEVEL: info

envFromSecrets:
  - name: REDIS_PASSWORD
    secretName: redis-secrets
    secretKey: password

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 75

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
            app: redis
      ports:
      - protocol: TCP
        port: 6379
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Service 7: Dispatch (Go, RabbitMQ)

#### values.yaml
```yaml
name: dispatch
tier: backend
replicas: 1
port: 8080

image:
  repository: robotshop
  name: dispatch
  version: v1.0.0

service:
  type: ClusterIP
  port: 80

env:
  RABBITMQ_HOST: rabbitmq
  RABBITMQ_PORT: "5672"
  LOG_LEVEL: info

envFromSecrets:
  - name: RABBITMQ_USER
    secretName: rabbitmq-secrets
    secretKey: username
  - name: RABBITMQ_PASSWORD
    secretName: rabbitmq-secrets
    secretKey: password

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

autoscaling:
  enabled: false  # Single instance worker

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  egress:
    - to:
      - podSelector:
          matchLabels:
            app: rabbitmq
      ports:
      - protocol: TCP
        port: 5672
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53

statefulSet:
  enabled: false
```

---

### Databases (MongoDB, MySQL, Redis, RabbitMQ)

#### MongoDB values.yaml
```yaml
name: mongodb
tier: database
port: 27017

image:
  repository: mongo
  name: mongo
  version: "5.0"

envFromSecrets:
  - name: MONGO_INITDB_ROOT_USERNAME
    secretName: mongodb-secrets
    secretKey: username
  - name: MONGO_INITDB_ROOT_PASSWORD
    secretName: mongodb-secrets
    secretKey: password

resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"

statefulSet:
  enabled: true

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

autoscaling:
  enabled: false

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - podSelector:
          matchLabels:
            tier: backend
      ports:
      - protocol: TCP
        port: 27017
  egress:
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53
```

#### MySQL values.yaml
```yaml
name: mysql
tier: database
port: 3306

image:
  repository: mysql
  name: mysql
  version: "8.0"

envFromSecrets:
  - name: MYSQL_ROOT_PASSWORD
    secretName: mysql-secrets
    secretKey: root-password
  - name: MYSQL_USER
    secretName: mysql-secrets
    secretKey: username
  - name: MYSQL_PASSWORD
    secretName: mysql-secrets
    secretKey: password

resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"

statefulSet:
  enabled: true

volumeMounts:
  - name: data
    mountPath: /var/lib/mysql

volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi

autoscaling:
  enabled: false

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - podSelector:
          matchLabels:
            tier: backend
      ports:
      - protocol: TCP
        port: 3306
  egress:
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

## Commands and Workflow

### Step 1: Create Directory Structure

```bash
cd /home/abdelrahman/Desktop/DevOps/robot-shop/helm

# Create _common directory
mkdir -p _common/templates

# Create service directories
mkdir -p catalogue/templates
mkdir -p payment/templates
mkdir -p user/templates
mkdir -p ratings/templates
mkdir -p shipping/templates
mkdir -p cart/templates
mkdir -p dispatch/templates

# Create database directories
mkdir -p mongodb/templates
mkdir -p mysql/templates
mkdir -p redis/templates
mkdir -p rabbitmq/templates
```

### Step 2: Create Common Templates

Use the templates shown above to create files in `_common/templates/`:

```bash
# Create _deployment.yaml
cat > _common/templates/_deployment.yaml << 'EOF'
[Template content from above]
EOF

# Create _service.yaml
cat > _common/templates/_service.yaml << 'EOF'
[Template content from above]
EOF

# etc.
```

### Step 3: Create Service Charts

For each service:

```bash
# Example: catalogue
cat > catalogue/Chart.yaml << 'EOF'
apiVersion: v2
name: catalogue
description: Product catalogue service
type: application
version: 0.1.0
appVersion: "1.0"
EOF

cat > catalogue/values.yaml << 'EOF'
[values.yaml content from above]
EOF

cat > catalogue/templates/deployment.yaml << 'EOF'
{{- include "common.deployment" . -}}
EOF

cat > catalogue/templates/service.yaml << 'EOF'
{{- include "common.service" . -}}
EOF

cat > catalogue/templates/hpa.yaml << 'EOF'
{{- include "common.hpa" . -}}
EOF

cat > catalogue/templates/networkpolicy.yaml << 'EOF'
{{- include "common.networkpolicy" . -}}
EOF
```

### Step 4: Validate Charts

```bash
# Validate catalogue chart
helm lint catalogue/

# Validate all charts
for chart in catalogue payment user ratings shipping cart dispatch mongodb mysql; do
  echo "Validating $chart..."
  helm lint $chart/
done
```

### Step 5: Dry Run (See What Will Be Created)

```bash
# See what catalogue will deploy
helm template catalogue ./catalogue --namespace robot-shop

# See what payment will deploy with custom values
helm template payment ./payment \
  --namespace robot-shop \
  --set replicas=5 \
  --set autoscaling.maxReplicas=15
```

### Step 6: Install Charts

```bash
# Create namespace
kubectl create namespace robot-shop

# Create secrets (BEFORE installing)
kubectl create secret generic mongodb-secrets \
  --from-literal=username=admin \
  --from-literal=password=SecurePassword123! \
  --namespace robot-shop

kubectl create secret generic mysql-secrets \
  --from-literal=username=root \
  --from-literal=password=SecurePassword456! \
  --namespace robot-shop

# etc.

# Install charts individually
helm install catalogue ./catalogue --namespace robot-shop
helm install payment ./payment --namespace robot-shop
helm install user ./user --namespace robot-shop
helm install mongodb ./mongodb --namespace robot-shop
# ... etc

# Or use helm install with multiple charts
helm install robot-shop-services . \
  --namespace robot-shop \
  --values values.yaml
```

### Step 7: Check Deployments

```bash
# List Helm releases
helm list -n robot-shop

# Check pods
kubectl get pods -n robot-shop

# Check services
kubectl get svc -n robot-shop

# Check HPAs
kubectl get hpa -n robot-shop

# Check NetworkPolicies
kubectl get networkpolicies -n robot-shop
```

### Step 8: Update Values (Without Changing Code)

```bash
# Change catalogue replicas (without editing files)
helm upgrade catalogue ./catalogue \
  --namespace robot-shop \
  --set replicas=5

# Change payment autoscaling
helm upgrade payment ./payment \
  --namespace robot-shop \
  --set autoscaling.maxReplicas=15 \
  --set autoscaling.targetCPU=50

# Check the change
helm get values payment -n robot-shop
```

### Step 9: Update Template (All Charts Get Fix)

```bash
# Edit _common/templates/_deployment.yaml
vim _common/templates/_deployment.yaml

# All services using it automatically get the fix
helm upgrade catalogue ./catalogue --namespace robot-shop
helm upgrade payment ./payment --namespace robot-shop
# (no code change in catalogue/templates/deployment.yaml needed)
```

### Step 10: Rollback if Needed

```bash
# See release history
helm history catalogue -n robot-shop

# Rollback to previous release
helm rollback catalogue 1 -n robot-shop
```

---

## Complete Directory Tree (Final Structure)

```
helm/
├── _common/
│   ├── Chart.yaml
│   └── templates/
│       ├── _configmap.yaml
│       ├── _deployment.yaml
│       ├── _hpa.yaml
│       ├── _ingress.yaml
│       ├── _networkpolicy.yaml
│       ├── _secret.yaml
│       ├── _service.yaml
│       └── _statefulset.yaml
│
├── catalogue/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml          (1 line)
│       ├── hpa.yaml                 (1 line)
│       ├── networkpolicy.yaml       (1 line)
│       └── service.yaml             (1 line)
│
├── payment/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── networkpolicy.yaml
│       └── service.yaml
│
├── user/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── networkpolicy.yaml
│       └── service.yaml
│
├── ratings/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── networkpolicy.yaml
│       └── service.yaml
│
├── shipping/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── networkpolicy.yaml
│       └── service.yaml
│
├── cart/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── hpa.yaml
│       ├── networkpolicy.yaml
│       └── service.yaml
│
├── dispatch/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── networkpolicy.yaml
│
├── mongodb/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── networkpolicy.yaml
│       ├── service.yaml
│       └── statefulset.yaml
│
├── mysql/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── networkpolicy.yaml
│       ├── service.yaml
│       └── statefulset.yaml
│
├── redis/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── networkpolicy.yaml
│       ├── service.yaml
│       └── statefulset.yaml
│
├── rabbitmq/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── networkpolicy.yaml
│       ├── service.yaml
│       └── statefulset.yaml
│
├── web/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── ingress.yaml
│       ├── networkpolicy.yaml
│       ├── service.yaml
│       └── configmap.yaml
│
└── robot-shop/                       (Umbrella chart - coming next)
    ├── Chart.yaml
    ├── values.yaml
    ├── charts/                       (Dependencies)
    │   ├── catalogue/
    │   ├── payment/
    │   ├── user/
    │   ├── ratings/
    │   ├── shipping/
    │   ├── cart/
    │   ├── dispatch/
    │   ├── mongodb/
    │   ├── mysql/
    │   ├── redis/
    │   ├── rabbitmq/
    │   └── web/
    └── templates/
        └── NOTES.txt
```

---

## Key Takeaways

### 1. Common Templates (Reusable)
- Live in `_common/templates/`
- File names start with `_`
- Wrapped in `{{- define "common.xxx" -}}`
- Used by all services

### 2. Service Charts (Specific)
- Have `Chart.yaml` and `values.yaml`
- In `templates/`, include common templates with one line
- Each has **own values** for customization
- Can be deployed independently

### 3. Per-Service Customization
- Each service has **different values.yaml**
- Same templates, different configs
- Change by updating values:
  ```bash
  helm upgrade service ./service --set key=value
  ```

### 4. When to Change Templates vs Values
- **Change templates** (`_common/templates/*.yaml`) when:
  - Adding new functionality to all services
  - Fixing bugs in resource generation
  - Changing structure
  - All changes apply to all 7 services instantly

- **Change values** (`service/values.yaml`) when:
  - Adjusting service-specific config
  - Changing replicas, resource limits, etc.
  - Can be done per-service independently

### 5. Adding New Services
1. Create new directory: `mkdir newservice/templates`
2. Create Chart.yaml with service details
3. Create values.yaml with service config
4. Create template files: `deployment.yaml`, `service.yaml`, etc.
   - Each file: `{{- include "common.xxx" . -}}`
5. Deploy: `helm install newservice ./newservice`

That's it! No duplicate code to maintain.

---

## Next Steps

1. **Create _common templates** (6 files with resource types)
2. **Create service charts** (12 charts total: 7 services + 4 databases + 1 web + 1 umbrella)
3. **Create umbrella chart** to deploy everything with one command
4. **Create values-prod.yaml** for production overrides
5. **Set up GitOps** with ArgoCD to manage deployments

Each step builds on the previous, and all follow the same pattern shown above.
