# Helm Templates Basics (Simple Guide)

This document explains the fundamentals needed to write Helm templates clearly and safely.

Next step guide:
- [Deployment-Template-From-Scratch.md](Deployment-Template-From-Scratch.md)

---

## 1) What Helm Templating Solves

Kubernetes YAML files are often repeated across services. Helm templates reduce duplication by replacing hardcoded values with variables from `values.yaml`.

Main result:
- one template structure,
- different outputs per service/environment.

---

## 2) Core Concepts

### Chart
A chart is a package that contains templates and values.

Typical structure:

```text
my-service/
├── Chart.yaml
├── values.yaml
└── templates/
```

### Template
A template is a Kubernetes manifest with dynamic expressions like `{{ ... }}`.

### Values
Values are configuration data loaded from:
- chart `values.yaml`,
- parent/umbrella values,
- environment files (`-f values-prod.yaml`),
- CLI overrides (`--set ...`).

---

## 3) Helm Template Syntax Basics

This section explains each Helm syntax part with three points:
1) what it is, 2) why it exists, 3) how to use it.

### Step 1: Template delimiters `{{ ... }}`

Purpose:
- mark dynamic expressions inside YAML.

Use:

```yaml
name: {{ .Values.name }}
```

Result:
- Helm replaces expression output into final manifest.

### Step 2: Value lookup `.Values...`

Purpose:
- read configuration from `values.yaml` instead of hardcoding.

Use:

```yaml
replicas: {{ .Values.replicas }}
image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
```

Matching values:

```yaml
replicas: 2
image:
	repository: robotshop/catalogue
	tag: "2.1.0"
```

### Step 3: Pipelines `|` and functions

Purpose:
- transform values before rendering.

Use:

```yaml
replicas: {{ .Values.replicas | default 1 }}
value: {{ .Values.logLevel | quote }}
name: {{ .Values.name | lower }}
```

Common functions:
- `default`: fallback value,
- `quote`: enforce YAML string,
- `upper`/`lower`: normalize text,
- `toYaml`: render object as YAML.

### Step 4: Conditionals `if / else / end`

Purpose:
- render sections only when required.

Use:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
{{- end }}
```

Practical case:
- optional resources (Ingress, HPA, NetworkPolicy) should be wrapped in `if`.

### Step 5: Loops `range`

Purpose:
- render repeated blocks from lists or maps.

Map example (`env`):

```yaml
{{- range $key, $value := .Values.env }}
- name: {{ $key }}
	value: {{ $value | quote }}
{{- end }}
```

List example (`envFromSecrets`):

```yaml
{{- range .Values.envFromSecrets }}
- name: {{ .name }}
	valueFrom:
		secretKeyRef:
			name: {{ .secretName }}
			key: {{ .secretKey }}
{{- end }}
```

### Step 6: Whitespace control `{{-` and `-}}`

Purpose:
- avoid empty lines and malformed YAML output.

Use:

```yaml
{{- if .Values.resources }}
resources:
	{{- toYaml .Values.resources | nindent 2 }}
{{- end }}
```

Guideline:
- prefer `{{- ... }}` in control blocks (`if`, `range`) for clean output.

### Step 7: YAML indentation helpers (`toYaml`, `nindent`)

Purpose:
- render nested objects safely without manual spacing mistakes.

Use:

```yaml
resources:
	{{- toYaml .Values.resources | nindent 2 }}
```

Why:
- manual indentation is the most common template failure source.

### Step 8: Built-in Helm objects

Purpose:
- access release and chart metadata.

Use:

```yaml
namespace: {{ .Release.Namespace }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
```

Practical rule:
- use `.Release.Namespace` instead of hardcoding namespace names.

### Step 9: A simple writing workflow

1. Write static valid YAML first.
2. Replace changing values with `.Values...`.
3. Add `default` for non-required scalar values.
4. Add `if` around optional blocks.
5. Add `range` for repeated sections.
6. Use `toYaml` + `nindent` for object blocks.
7. Validate with:

```bash
helm lint .
helm template test .
```

---

## 4) Values Priority (Important)

Helm applies values from lower to higher priority:

1. subchart defaults (`charts/<service>/values.yaml`)
2. umbrella chart values (`helm/robot-shop/values.yaml`)
3. environment file (`-f values-dev.yaml`, `-f values-prod.yaml`)
4. CLI override (`--set key=value`)

Last value wins.

---

## 5) Common Pattern: Shared Templates + Service Charts

In multi-service architecture, common templates are stored in a shared chart (for example `_common`) and included by service charts.

Shared template definition:

```yaml
{{- define "common.deployment" -}}
# deployment template body
{{- end -}}
```

Service usage:

```yaml
{{- include "common.deployment" . -}}
```

The `.` passes chart context and values to the shared template.

---

## 6) Why This Approach Is Useful

### Technical benefits
- less duplicated YAML,
- consistent structure across services,
- faster updates when standards change,
- easier review and maintenance.

### Team benefits
- clear separation between template logic and service configuration,
- easier onboarding,
- predictable deployment patterns.

---

## 7) Production-Level Expectations

A production-ready template usually includes:
- `resources` (requests/limits),
- `livenessProbe` and `readinessProbe`,
- secure secret references (not plain secrets in Git),
- optional HPA,
- optional NetworkPolicy,
- environment-specific values files.

Validation workflow:

```bash
helm lint .
helm template my-release . -f values-dev.yaml
helm template my-release . -f values-prod.yaml
```

---

## 8) Common Mistakes to Avoid

- wrong indentation in templates,
- missing defaults for optional values,
- mixing secrets into plain values files,
- skipping `helm template` validation before install,
- forgetting value layering behavior.

---

## 9) Next File

For a full step-by-step practical implementation, including a complete `deployment.yaml` and matching `values.yaml`, continue with:

- [Deployment-Template-From-Scratch.md](Deployment-Template-From-Scratch.md)
