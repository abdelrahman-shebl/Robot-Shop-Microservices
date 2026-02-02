# Chart.yaml Reference Guide
## Umbrella Chart & Library Chart Syntax

This guide explains the correct syntax for Chart.yaml files in the robot-shop project.

---

## Table of Contents

1. [Umbrella Chart (Main)](#umbrella-chart-main)
2. [Library Chart (_common)](#library-chart-_common)
3. [Service Charts](#service-charts)
4. [Dependencies Syntax](#dependencies-syntax)
5. [Common Errors](#common-errors)

---

## Umbrella Chart (Main)

The umbrella chart lives at `robot-shop/Chart.yaml` and orchestrates all subcharts.

### File: `robot-shop/Chart.yaml`

```yaml
apiVersion: v2                      # Helm 3 format (required)
name: robot-shop                    # Chart name
description: A microservices e-commerce application
type: application                   # Type: application or library
version: 1.0.0                      # Umbrella chart version (increment on changes)
appVersion: "2.1.0"                 # Robot-shop application version

keywords:
  - microservices
  - e-commerce
home: https://github.com/instana/robot-shop
maintainers:
  - name: DevOps Team
    email: devops@example.com

dependencies:
  # Library chart (templates and helpers)
  - name: common
    version: "0.1.0"
    repository: "file://./charts/_common"
    import-values:
      - child: common

  # External chart from repository
  - name: redis
    version: "18.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled

  # Local service charts
  - name: user
    version: "0.1.0"
    repository: "file://./charts/user"
    condition: user.enabled

  - name: web
    version: "0.1.0"
    repository: "file://./charts/web"
    condition: web.enabled

  - name: mysql
    version: "0.1.0"
    repository: "file://./charts/mysql"
    condition: mysql.enabled

  - name: ratings
    version: "0.1.0"
    repository: "file://./charts/ratings"
    condition: ratings.enabled

  - name: dispatch
    version: "0.1.0"
    repository: "file://./charts/dispatch"
    condition: dispatch.enabled
```

### Syntax Explanation

| Field | Example | Purpose |
|-------|---------|---------|
| `apiVersion` | `v2` | Helm 3 format (must be v2) |
| `name` | `robot-shop` | Chart name (no spaces, lowercase) |
| `type` | `application` | Must be "application" for deployable charts |
| `version` | `1.0.0` | Umbrella chart version (increment on changes) |
| `appVersion` | `"2.1.0"` | Application version (robot-shop version) |
| `dependencies` | List | All subcharts this chart needs |

---

## Library Chart (_common)

The library chart provides reusable templates (NOT a deployable application).

### File: `robot-shop/charts/_common/Chart.yaml`

Create this file with:

```yaml
apiVersion: v2
name: common
description: Common templates and helpers for robot-shop
type: library                       # TYPE: library (not application)
version: 0.1.0
appVersion: "1.0.0"

keywords:
  - templates
  - helpers
maintainers:
  - name: DevOps Team
    email: devops@example.com
```

### Key Difference: type: library

- **`type: library`** - Templates only (no Pods/Services deployed)
- **`type: application`** - Deployable (creates Pods/Services)

### Library Chart Purpose

- Contains reusable template definitions (in `_common/templates/`)
- Used by other charts via `{{- include "common.deployment" . -}}`
- NOT deployed directly (no `helm install` on this chart)
- Shared across user, web, mysql, ratings, dispatch charts

---

## Service Charts

Each microservice chart (user, web, mysql, ratings, dispatch) has its own Chart.yaml.

### File: `robot-shop/charts/user/Chart.yaml`

```yaml
apiVersion: v2
name: user
description: User microservice for robot-shop
type: application                   # Service charts are deployable
version: 0.1.0
appVersion: "2.1.0"

dependencies:
  # Reference the library chart
  - name: common
    version: "0.1.0"
    repository: "file://../_common"  # Relative path to _common
```

### Key Points

- Each service chart has `type: application`
- Each service depends on `common` library for templates
- Path to common is relative: `file://../_common` (go up one level to _common)

---

## Dependencies Syntax

### Understanding Dependency Fields

```yaml
dependencies:
  - name: CHART_NAME                         # Name in Chart repo
    version: "VERSION_CONSTRAINT"            # Version to download
    repository: "REPOSITORY_URL"             # Where to find chart
    condition: VALUES_PATH.enabled           # Enable/disable flag
    alias: ALTERNATIVE_NAME                  # Optional: rename chart
    import-values:                           # Optional: import values
      - child: CHART_VALUES
        parent: PARENT_VALUES
```

### Examples

#### Local Chart (file:// path)

```yaml
- name: user
  version: "0.1.0"
  repository: "file://./charts/user"   # Local directory
  condition: user.enabled              # Enable/disable: `user.enabled: true`
```

**When to use:** Your custom charts already in `charts/` directory

#### Remote Chart (HTTP URL)

```yaml
- name: redis
  version: "18.x.x"
  repository: "https://charts.bitnami.com/bitnami"  # Remote repository
  condition: redis.enabled
```

**When to use:** External charts like Redis, Prometheus from internet

#### Library Chart (file:// path)

```yaml
- name: common
  version: "0.1.0"
  repository: "file://./charts/_common"  # Relative path works too
  import-values:
    - child: common                      # Import from common chart
```

**When to use:** Template library shared across charts

---

## Version Constraints

### Version Syntax

```yaml
dependencies:
  # Exact version
  - version: "18.1.0"               # Exactly 18.1.0
  
  # Patch updates allowed
  - version: "18.1.x"               # 18.1.0-18.1.9
  
  # Minor updates allowed
  - version: "18.x.x"               # 18.0.0-18.9.9
  
  # Any version
  - version: "*"                    # Latest compatible
```

### Examples

```yaml
dependencies:
  - name: common
    version: "0.1.0"                # Exact: must be 0.1.0

  - name: redis
    version: "18.x.x"               # Any 18.x version (18.0, 18.1, 18.5, etc)

  - name: user
    version: "0.1.0"                # Exact: must be 0.1.0
```

---

## Directory Structure

```
robot-shop/
├── Chart.yaml                          ← Umbrella chart (main)
├── values.yaml
├── charts/
│   ├── _common/                        ← Library chart
│   │   ├── Chart.yaml                  ← type: library
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── _deployment.yaml
│   │       ├── _statefulset.yaml
│   │       ├── _service.yaml
│   │       ├── _hpa.yaml
│   │       ├── _ingress.yaml
│   │       ├── _networkpolicy.yaml
│   │       └── _secret.yaml
│   │
│   ├── user/                           ← Service chart
│   │   ├── Chart.yaml                  ← type: application
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── hpa.yaml
│   │       └── networkpolicy.yaml
│   │
│   ├── web/                            ← Service chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   ├── mysql/                          ← Service chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   ├── ratings/                        ← Service chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   └── dispatch/                       ← Service chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
```

---

## Common Errors

### Error 1: Wrong Chart Type for Library

❌ WRONG:
```yaml
# _common/Chart.yaml
type: application    # ← WRONG for templates library
```

✅ CORRECT:
```yaml
# _common/Chart.yaml
type: library        # ← CORRECT for template library
```

**Why:** Library charts contain only templates, not deployable resources.

---

### Error 2: Wrong Repository Path

❌ WRONG:
```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: user
    repository: "file://charts/user"     # ← Missing ./
```

✅ CORRECT:
```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: user
    repository: "file://./charts/user"   # ← Must have ./
```

---

### Error 3: Missing or Wrong Condition

❌ WRONG:
```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: user
    # ← Missing condition field
```

✅ CORRECT:
```yaml
# robot-shop/Chart.yaml
dependencies:
  - name: user
    condition: user.enabled              # ← Allows enable/disable
```

Then in `values.yaml`:
```yaml
user:
  enabled: true    # Enable this subchart
```

---

### Error 4: Inconsistent Version Numbers

❌ WRONG:
```yaml
# robot-shop/Chart.yaml
version: 1.0.0

dependencies:
  - name: user
    version: "1.0.0"      # ← Service chart shouldn't match umbrella
```

✅ CORRECT:
```yaml
# robot-shop/Chart.yaml
version: 1.0.0            # Umbrella chart version

dependencies:
  - name: user
    version: "0.1.0"      # ← Service chart has own version
```

**Why:** Each chart has independent versioning.

---

## Commands

### Update Dependencies

```bash
cd /home/abdelrahman/Desktop/DevOps/robot-shop/helm/robot-shop

# Download all dependencies (from Chart.yaml)
helm dependency update

# See what was downloaded
helm dependency list

# Result: Shows common, redis, user, web, mysql, ratings, dispatch
```

### Validate Chart Structure

```bash
# Check for YAML errors
helm lint robot-shop/

# Render templates to see final YAML
helm template robot-shop ./robot-shop --debug

# Dry-run install (don't actually create resources)
helm install robot-shop ./robot-shop --dry-run --namespace robot-shop
```

### Deploy

```bash
# Install all subcharts
helm install robot-shop ./robot-shop --namespace robot-shop --create-namespace

# Check what was deployed
helm list -n robot-shop
kubectl get pods -n robot-shop
```

---

## Summary

### Three Chart Types in Your Project

1. **Umbrella Chart** (`robot-shop/Chart.yaml`)
   - `type: application`
   - Contains: Common, Redis, User, Web, MySQL, Ratings, Dispatch
   - Deploy with: `helm install robot-shop ./robot-shop`

2. **Library Chart** (`robot-shop/charts/_common/Chart.yaml`)
   - `type: library`
   - Contains: Reusable template definitions
   - NOT deployed directly
   - Used by all service charts

3. **Service Charts** (`robot-shop/charts/{user,web,mysql,ratings,dispatch}/Chart.yaml`)
   - `type: application`
   - Contains: Their specific templates
   - Depend on library chart (_common)
   - Deployed via umbrella chart

### Key Rules

- Umbrella: `type: application` + dependencies list
- Library: `type: library` + reusable templates
- Services: `type: application` + depend on library
- Paths: Use `file://./` for local charts
- Version: Each chart has independent version
- Condition: Every dependency needs `condition: NAME.enabled`

### Next: Fix Chart.yaml Files

1. Create `robot-shop/charts/_common/Chart.yaml` with `type: library`
2. Verify all service charts have `type: application`
3. Run `helm dependency update` to validate syntax
4. Run `helm lint` to check for errors
