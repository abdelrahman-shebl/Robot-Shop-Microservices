# Deployment Template From Scratch

This guide is the practical continuation of:
- [Helm_templates.md](Helm_templates.md)

Goal: create a reusable Deployment template, define its `values.yaml`, include it in subcharts, and apply production-level practices.

---

## 1) Start With a Chart Skeleton

```bash
helm create sample-service
```

Keep the standard structure:

```text
sample-service/
├── Chart.yaml
├── values.yaml
└── templates/
    └── deployment.yaml
```

---

## 2) Build `templates/deployment.yaml` Step by Step

Instead of writing the full Helm template directly, start with hardcoded Kubernetes YAML and convert each section.

### Step 2.1: Start from hardcoded Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-service
  namespace: default
  labels:
    app: sample-service
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-service
  template:
    metadata:
      labels:
        app: sample-service
        tier: backend
    spec:
      containers:
        - name: sample-service
          image: robotshop/sample-service:2.1.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
```

This YAML works, but it cannot be reused easily across services or environments.

### Step 2.2: Convert metadata and replicas to Helm syntax

Hardcoded part:

```yaml
name: sample-service
namespace: default
replicas: 2
```

Helm version:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier | default "backend" }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier | default "backend" }}
    spec:
      containers: []
```

Purpose:
- make service identity and replica count configurable,
- avoid hardcoding namespace,
- preserve correct Kubernetes label matching.

### Step 2.3: Convert image and port

Hardcoded part:

```yaml
image: robotshop/sample-service:2.1.0
imagePullPolicy: IfNotPresent
containerPort: 8080
```

Helm version:

```yaml
spec:
  containers:
    - name: {{ .Values.name }}
      image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
      imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
      ports:
        - containerPort: {{ .Values.port | default 8080 }}
          name: http
```

Purpose:
- image tag changes per release without editing template,
- port stays reusable for different apps,
- pull policy can be tuned per environment.

### Step 2.4: Convert environment variables (plain + secret refs)

Hardcoded plain env example:

```yaml
env:
  - name: LOG_LEVEL
    value: "info"
```

Hardcoded secret env example:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: password
```

Helm version (supports both patterns):

```yaml
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
```

Purpose:
- keep non-sensitive config in values files,
- keep sensitive data in Kubernetes Secrets,
- render `env` only when needed.

### Step 2.5: Convert resources and probes

Hardcoded resources/probes example:

```yaml
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

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
```

Helm version:

```yaml
          {{- if .Values.resources }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- end }}

          {{- if .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          {{- end }}

          {{- if .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          {{- end }}
```

Purpose:
- production safety with resource boundaries,
- better availability via health checks,
- optional rendering when a service does not need a probe block.

### Step 2.6: Final full template (assembled)

After building each section, the full result should look like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ .Values.name }}
    tier: {{ .Values.tier | default "backend" }}
spec:
  replicas: {{ .Values.replicas | default 1 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
        tier: {{ .Values.tier | default "backend" }}
    spec:
      containers:
        - name: {{ .Values.name }}
          image: {{ .Values.image.repository }}/{{ .Values.image.name }}:{{ .Values.image.version }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - containerPort: {{ .Values.port | default 8080 }}
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
            {{- toYaml .Values.resources | nindent 12 }}
          {{- end }}

          {{- if .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml .Values.livenessProbe | nindent 12 }}
          {{- end }}

          {{- if .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml .Values.readinessProbe | nindent 12 }}
          {{- end }}
```

### Why this template works
- starts from required Kubernetes structure,
- adds one concern at a time (image, env, probes, resources),
- stays easy to debug when a section fails,
- remains production-friendly without unnecessary complexity.

---

## 3) Create `values.yaml` For This Template

```yaml
name: sample-service
tier: backend
replicas: 2
port: 8080

image:
  repository: robotshop
  name: sample-service
  version: "2.1.0"
  pullPolicy: IfNotPresent

env:
  LOG_LEVEL: info
  APP_MODE: production

envFromSecrets:
  - name: DB_USERNAME
    secretName: app-secrets
    secretKey: username
  - name: DB_PASSWORD
    secretName: app-secrets
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
```

This values file is a safe default base for most stateless API services.

---

## 4) Include Templates in Subcharts (Shared Pattern)

When a shared `_common` chart is used, put template logic in `_common`, then include it in each subchart.

### Shared chart (`charts/_common/templates/_deployment.yaml`)

```yaml
{{- define "common.deployment" -}}
# deployment template body
{{- end -}}
```

### Service subchart (`charts/user/templates/deployment.yaml`)

```yaml
{{- include "common.deployment" . -}}
```

This gives one deployment standard for all services while allowing service-specific behavior through each service `values.yaml`.

---

## 5) How Values Work Across Subchart and Umbrella

For service `user`:

1. `charts/user/values.yaml` defines defaults.
2. umbrella `values.yaml` overrides with:

```yaml
user:
  replicas: 3
```

3. environment file overrides again:

```yaml
user:
  replicas: 5
```

Final effective value in production: `5`.

---

## 6) Benefits of This Template Model

- faster service creation,
- same deployment quality across services,
- easier upgrades and bug fixes,
- clear separation between logic (templates) and config (values),
- safe scaling through environment-specific values.

---

## 7) Production-Level Checklist

Before deployment, confirm:

- resources are defined,
- probes are configured,
- secrets are referenced (not hardcoded),
- chart renders correctly in dev and prod values,
- optional autoscaling/network policies are added where needed.

Validation commands:

```bash
helm lint .
helm template sample . -f values.yaml
helm template sample . -f values-prod.yaml
helm install sample . --dry-run --debug
```

---

## 8) Troubleshooting Notes

### Template renders invalid YAML
Cause: indentation issues in conditional blocks.
Fix: use `toYaml` + `nindent` consistently.

### Value does not override as expected
Cause: values file order.
Fix: ensure override file is passed after base file.

### Secret variable is empty in container
Cause: missing secret key or wrong namespace.
Fix: verify secret name/key and deployment namespace.

---

## 9) Suggested Next Step

After Deployment template setup, add matching reusable templates for:
- `Service`,
- `HPA`,
- `NetworkPolicy`,
- `Ingress` (only for externally exposed services).

This creates a complete production-ready template stack for subcharts.
