# ServiceMonitors: MySQL and MongoDB Exporters

Parent file: [kube-prometheus-stack.md](kube-prometheus-stack.md)

---

## 1) What a ServiceMonitor Is

A `ServiceMonitor` is a Kubernetes CRD installed by the Prometheus Operator. It tells Prometheus exactly where and how to scrape metrics from a Kubernetes Service — without modifying Prometheus configuration directly.

### How it works

```
  Your App (e.g., MySQL)
    │
    │  exposes /metrics on port 9104
    ▼
  Kubernetes Service (port 9104)
    │
    │  selected by
    ▼
  ServiceMonitor (CRD)
    │
    │  Prometheus Operator reads this and rewrites Prometheus scrape_configs
    ▼
  Prometheus scrapes /metrics on schedule
```

You never edit Prometheus config directly. You deploy a `ServiceMonitor` alongside your application, and the Operator picks it up automatically — provided the ServiceMonitor discovery rules are configured correctly (see [kube-prometheus-stack.md](kube-prometheus-stack.md) section 5).

---

## 2) Prometheus Exporters: The Concept

Most databases and middleware do not expose Prometheus-format metrics natively. Exporters are small sidecar services that:
1. Connect to the target application (MySQL, MongoDB, Redis, etc.).
2. Query its native metrics API.
3. Translate and re-expose those metrics in Prometheus text format on a `/metrics` HTTP endpoint.

The exporter needs credentials to connect to the app. Those credentials must not be hardcoded in the values file — instead, both exporters support referencing an existing Kubernetes Secret.

---

## 3) MySQL Exporter

### How it connects to MySQL

The exporter runs as a separate Pod in the cluster. It connects to the MySQL Service using standard MySQL credentials. It exposes metrics on port 9104.

### Values file breakdown

```yaml
# terraform/modules/addons/values/prometheus-mysql-values.yaml

mysql:
  # The Kubernetes Service name of your MySQL instance.
  # In this project, the robot-shop MySQL service is named "mysql".
  host: "mysql"
  port: 3306
  
  # The MySQL user the exporter uses to connect.
  # This user needs only SELECT and PROCESS privileges — never use root in production.
  user: "root"
  
  # Secret reference for the MySQL password.
  # The exporter reads the password from this Kubernetes Secret at runtime.
  existingPasswordSecret:
    name: "mysql-secrets"           # name of the Kubernetes Secret
    key: "MYSQL_ROOT_PASSWORD"      # key within the secret's data map

  # Never do this in production:
  # pass: "change_me_root_password"

# Creates a ServiceMonitor so Prometheus automatically discovers this exporter.
serviceMonitor:
  enabled: true

# Label added to the exporter pod.
# Useful for filtering in Grafana (e.g., show metrics only from MySQL exporter pods).
podLabels:
  app: mysql-exporter
```

### The Kubernetes Secret it references

```yaml
# The secret that already exists in the cluster (created by your app infra, not by this chart):
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secrets
  namespace: robot-shop
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: "your-password-here"
```

The exporter chart reads `mysql-secrets` and injects the value of `MYSQL_ROOT_PASSWORD` as the MySQL connection password. The actual password never appears in the Helm values file.

### What metrics it provides

Once running, the exporter exposes metrics including:
```promql
# Connection count
mysql_global_status_threads_connected

# Slow queries
rate(mysql_global_status_slow_queries[5m])

# InnoDB buffer pool hit rate
mysql_global_status_innodb_buffer_pool_reads
mysql_global_status_innodb_buffer_pool_read_requests

# Table lock waits
mysql_global_status_table_locks_waited
```

The recommended Grafana dashboard is **ID 7362** (MySQL Overview), already configured in the prometheus-values.yaml.

---

## 4) MongoDB Exporter

### Values file breakdown

```yaml
# terraform/modules/addons/values/prometheus-mongo-values.yaml

serviceMonitor:
  enabled: true    # creates a ServiceMonitor for Prometheus auto-discovery

podLabels:
  app: mongodb-exporter

# Secret reference for the MongoDB connection URI.
# The exporter needs the full MongoDB URI including credentials.
existingSecret:
  name: "mongo-secrets"     # name of the Kubernetes Secret
  key: "MONGODB_URI"         # key within the secret's data map

# Never hardcode credentials:
# mongodb:
#   uri: "mongodb://admin:password@mongodb:27017/?authSource=admin"
```

### The Kubernetes Secret it references

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongo-secrets
  namespace: robot-shop
type: Opaque
stringData:
  MONGODB_URI: "mongodb://admin:password@mongodb:27017/?authSource=admin"
```

The URI format is standard MongoDB connection string. It includes:
- Protocol: `mongodb://`
- Credentials: `username:password@`
- Host and port: `mongodb:27017` (Kubernetes Service name)
- Auth database: `?authSource=admin`

### What metrics it provides

```promql
# Active connections
mongodb_connections{state="current"}

# Operations per second
rate(mongodb_op_counters_total[5m])

# Replication lag (replica sets)
mongodb_mongod_replset_member_optime_date

# Collection sizes
mongodb_collstats_storageSize
```

---

## 5) How Secret References Work

Both exporters follow the same Kubernetes-native pattern for secret injection. Understanding this pattern helps when configuring any exporter.

### The flow

```
Kubernetes Secret (pre-existing)
    │
    │  referenced by name + key in values.yaml
    ▼
Helm Chart creates a Pod
    │
    │  injects secret value as environment variable
    ▼
Exporter Pod reads env var at runtime
    │
    │  uses it as the connection credential
    ▼
Connects to MySQL / MongoDB
```

### The critical rule: the secret must exist before the chart installs

Neither the MySQL nor the MongoDB exporter chart creates the secret. The secret must already exist in the same namespace when Helm renders and deploys the exporter. If the secret is missing, the pod starts but crashes immediately with an authentication error.

In this project, secrets are managed externally via AWS Secrets Manager + External Secrets Operator. The ESO `ExternalSecret` creates the Kubernetes Secret before any exporter is deployed.

---

## 6) Verifying Exporters Are Working

### Check the exporter pod is running

```bash
# MySQL exporter
kubectl get pods -n robot-shop -l app=mysql-exporter

# MongoDB exporter
kubectl get pods -n robot-shop -l app=mongodb-exporter
```

### Check the ServiceMonitor exists

```bash
kubectl get servicemonitors --all-namespaces
```

### Check Prometheus has discovered the target

Open Prometheus UI → Status → Targets. Look for entries named after the exporter. Status should be `UP`.

```bash
kubectl port-forward -n monitoring svc/monitor-prometheus 9090:80
# Open: http://localhost:9090/targets
```

### Manually test the metrics endpoint

```bash
# Get the exporter pod name
POD=$(kubectl get pod -n robot-shop -l app=mysql-exporter -o name | head -1)

# Check the /metrics endpoint directly
kubectl exec -n robot-shop $POD -- wget -qO- http://localhost:9104/metrics | head -30
```

---

## 7) Writing Your Own ServiceMonitor

For custom applications that already expose Prometheus metrics on `/metrics`, you can write a `ServiceMonitor` directly without installing an exporter:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: robot-shop
  labels:
    # Add this if prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: true (default)
    # Not needed in this project since NilUsesHelmValues is set to false
    release: monitor
spec:
  # Which Services to scrape — must match actual Service labels
  selector:
    matchLabels:
      app: my-app
  
  # Namespaces to look for matching Services
  namespaceSelector:
    matchNames:
      - robot-shop

  endpoints:
    - port: http-metrics      # must match a named port on the Service
      path: /metrics          # default is /metrics
      interval: 30s           # how often to scrape
      scrapeTimeout: 10s      # timeout per scrape
      
      # If your app requires basic auth:
      # basicAuth:
      #   username:
      #     name: my-app-metrics-secret
      #     key: username
      #   password:
      #     name: my-app-metrics-secret
      #     key: password
```

The `selector.matchLabels` must match the labels on the Kubernetes Service (not the Pod). Prometheus Operator resolves the ServiceMonitor → Service → Pod chain automatically.
