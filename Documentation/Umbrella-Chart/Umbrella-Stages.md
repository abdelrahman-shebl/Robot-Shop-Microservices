# Umbrella Chart Stages (Build It Fast)

This file provides a stage-by-stage path for building an umbrella chart efficiently.

---

## Stage 1 — Build the Chart Structure

### Step 1: Create umbrella chart

```bash
cd helm
helm create robot-shop
```

This command creates the main chart skeleton that will manage all subcharts.

### Step 2: Keep only what umbrella needs

- Keep `Chart.yaml`
- Keep `values.yaml`
- Keep `charts/`
- Keep `templates/NOTES.txt` (optional)
- Remove default workload templates if deployment is handled only through subcharts

Reason: in umbrella architecture, workloads are owned by subcharts, not by the parent chart templates.

### Step 3: Create `_common` library chart

Create `helm/robot-shop/charts/_common/Chart.yaml`:

```yaml
apiVersion: v2
name: common
description: Shared templates for robot-shop
type: library
version: 0.1.0
```

Create helper templates in `charts/_common/templates/` (for example `_deployment.yaml`, `_service.yaml`, `_hpa.yaml`).

The `_common` chart centralizes reusable template logic and keeps service charts consistent.

### Step 4: Create service charts in `charts/`

Required folders:

```text
user, web, mysql, ratings, dispatch, cart, catalogue, shipping, payment, mongodb
```

Each service chart should have:

- `Chart.yaml` with `type: application`
- `values.yaml` with service defaults
- `templates/` with service resources

This creates a clean separation: one chart per service, plus one shared library chart.

---

## Stage 2 — Wire Dependencies and Values

### Step 1: Add dependencies in umbrella `Chart.yaml`

Use local references like:

```yaml
repository: "file://./charts/user"
```

Pattern:

```yaml
dependencies:
  - name: common
    version: "0.1.0"
    repository: "file://./charts/_common"

  - name: user
    version: "0.1.0"
    repository: "file://./charts/user"
    condition: user.enabled
```

Do this for all service charts.

The `condition` key allows enabling or disabling each chart from values files.

### Step 2: Understand values order

Values are applied from lower to higher priority:

1. `charts/<service>/values.yaml`
2. umbrella `values.yaml`
3. `values-dev.yaml` or `values-prod.yaml`
4. `--set ...`

So environment files should contain only what changes by environment.

This approach avoids duplication and keeps production/staging/dev differences easy to review.

### Step 3: Example usage

```bash
cd helm/robot-shop

helm dependency update
helm lint .

# Dev render
helm template robot-shop . -f values-dev.yaml

# Prod render
helm template robot-shop . -f values-prod.yaml
```

`helm template` is useful for validating rendered manifests before install or upgrade.

### Step 4: Deploy

```bash
helm install robot-shop . -n robot-shop-dev --create-namespace -f values-dev.yaml
helm install robot-shop . -n robot-shop-prod --create-namespace -f values-prod.yaml
```

Separate namespaces help isolate environments and simplify operations.

---

## Quick Checklist

- `_common` is `type: library`
- all service charts are `type: application`
- every dependency path uses `file://./charts/...`
- every service dependency has `condition: <service>.enabled`
- `values.yaml` = shared defaults, env files = overrides only
