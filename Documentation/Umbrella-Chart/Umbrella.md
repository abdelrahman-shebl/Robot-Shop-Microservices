# Umbrella Chart (Simple Guide)

This guide explains a simple way to build an umbrella chart using the same structure as `helm/robot-shop`.

For a stage-based implementation flow, see:
- [Umbrella-Stages.md](Umbrella-Stages.md)

---

## 1) Create the Main (Umbrella) Chart

From the `helm/` directory:

```bash
helm create robot-shop
```

This creates:

```text
robot-shop/
├── Chart.yaml
├── values.yaml
├── templates/
└── charts/
```

In umbrella-chart style, `templates/` is usually minimal (for example, only `NOTES.txt`) because workloads are defined in subcharts under `charts/`.

---

## 2) Create the Required Folders in `charts/`

Inside `helm/robot-shop/charts/`, create the library chart and service charts:

```text
_common/
user/
web/
mysql/
ratings/
dispatch/
cart/
catalogue/
shipping/
payment/
mongodb/
```

### `_common` (Library Chart)

Purpose: shared templates (deployment/service/hpa helpers) reused by all service charts.

`charts/_common` should contain:

```text
charts/_common/
├── Chart.yaml         # type: library
├── values.yaml
└── templates/
   ├── _deployment.yaml
   ├── _service.yaml
   ├── _hpa.yaml
   └── ...
```

`charts/_common/Chart.yaml` example:

```yaml
apiVersion: v2
name: common
type: library
version: 0.1.0
```

Important: `type: library` means this chart provides template logic and is not deployed as standalone resources.

### Service charts

Each service folder (`user`, `web`, etc.) is a deployable chart:

```text
charts/user/
├── Chart.yaml
├── values.yaml
└── templates/
```

Service chart type should be `application` because each service renders Kubernetes objects.

---

## 3) Reference Subcharts in Main `Chart.yaml`

In `helm/robot-shop/Chart.yaml`, dependencies define which subcharts belong to the umbrella release.

### Local chart reference format

```yaml
repository: "file://./charts/<chart-name>"
```

### Example pattern

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

Use `condition: <name>.enabled` so each subchart can be enabled/disabled from values.

For external charts (for example `redis` and `rabbitmq`), use remote repository URLs and keep condition flags the same way.

---

## 4) How Values Flow (Simple)

Think in 3 layers:

1. **Subchart defaults** (`charts/<service>/values.yaml`)
2. **Umbrella defaults** (`helm/robot-shop/values.yaml`)
3. **Environment overrides** (`helm/robot-shop/values-dev.yaml` or `values-prod.yaml`)

Helm priority (last wins):

```text
subchart values.yaml
   -> umbrella values.yaml
   -> -f values-dev.yaml / -f values-prod.yaml
   -> --set key=value
```

### Simple example

Subchart (`charts/user/values.yaml`):

```yaml
replicas: 1
```

Umbrella (`values.yaml`):

```yaml
user:
  replicas: 2
```

Prod (`values-prod.yaml`):

```yaml
user:
  replicas: 5
```

Final value in prod: `5`.

This layering keeps defaults centralized while allowing small, clean environment-specific overrides.

---

## 5) Minimal Commands

From `helm/robot-shop`:

```bash
helm dependency update
helm lint .
helm template robot-shop . -f values-dev.yaml
helm template robot-shop . -f values-prod.yaml
```

Deploy example:

```bash
helm install robot-shop . -n robot-shop-dev --create-namespace -f values-dev.yaml
```

These commands validate dependencies and render output before a real install.

---

## 6) Practical Rules

- Keep `_common` as `type: library`.
- Keep service charts as `type: application`.
- Use `file://./charts/<name>` for local dependencies.
- Put shared defaults in umbrella `values.yaml`.
- Put only environment differences in `values-dev.yaml` and `values-prod.yaml`.
