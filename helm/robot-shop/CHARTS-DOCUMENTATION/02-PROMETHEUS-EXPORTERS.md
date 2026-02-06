# Prometheus Exporters: MySQL & MongoDB

## Overview

Exporters are specialized tools that convert metrics from databases into Prometheus format. The `prometheus-mysql-exporter` and `prometheus-mongodb-exporter` charts deploy these tools alongside their ServiceMonitors for automatic discovery.

**Why exporters?**
- Databases don't natively expose Prometheus metrics
- Exporters bridge this gap by scraping database APIs and converting to Prometheus format
- Prometheus discovers them automatically via ServiceMonitor CRDs

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Your Kubernetes Cluster                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐        ┌─────────────────────────────┐   │
│  │   MySQL Pod  │        │  Prometheus MySQL Exporter  │   │
│  │   :3306      │←───┬───│   Pod :9104                 │   │
│  │              │    │   │                             │   │
│  └──────────────┘    │   │  Reads metrics from MySQL   │   │
│                      │   │  Converts to Prometheus fmt │   │
│                      │   │                             │   │
│                      │   │  ServiceMonitor             │   │
│                      │   │  (Label: app=mysql-exporter)│   │
│                      │   └─────────────────────────────┘   │
│                      │                                      │
│                      └──→ Prometheus scrapes :9104          │
│                                                              │
│                           (Same for MongoDB)                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Prometheus MySQL Exporter Configuration

### 1. **Basic Configuration**

```yaml
prometheus-mysql-exporter:
  enabled: true
  
  mysql:
    host: "mysql"          # DNS name of MySQL service
    # port: 3306           # Default, can be overridden
    # user: "exporter"     # Database user
    # password: "secret"   # From secret in production
```

**How to modify for different environments:**

```yaml
prometheus-mysql-exporter:
  enabled: true
  
  mysql:
    # Development (in-cluster)
    host: "mysql"
    
    # Production (external database)
    # host: "mysql.us-east-1.rds.amazonaws.com"
    # port: 3306
    
    # With auth from secret
    auth:
      existingSecret: mysql-exporter-secret
      existingSecretPasswordKey: password
```

**Creating the secret:**
```bash
kubectl create secret generic mysql-exporter-secret \
  --from-literal=password=your-exporter-user-password
```

---

### 2. **ServiceMonitor Configuration**

```yaml
prometheus-mysql-exporter:
  serviceMonitor:
    enabled: true
    # interval: 30s       # Default scrape interval
    # scrapeTimeout: 10s  # How long to wait for response
```

**What ServiceMonitor does:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: prometheus-mysql-exporter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: prometheus-mysql-exporter
  
  endpoints:
    - port: metrics     # Port name in Service
      interval: 30s     # Scrape every 30 seconds
      path: /metrics    # Standard Prometheus endpoint
```

This CRD tells Prometheus Operator:
- **What to scrape**: The MySQL exporter's metrics endpoint
- **How often**: Every 30 seconds
- **Where to find it**: Via Service selector

Prometheus discovers this because:
```yaml
# In kube-prometheus-stack:
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # Discovers all ServiceMonitors
    serviceMonitorNamespaceSelector: {}              # Across all namespaces
```

---

### 3. **Pod Labels for Network Policies**

```yaml
prometheus-mysql-exporter:
  podLabels:
    app: mysql-exporter              # Label for network policies
    monitoring: enabled              # Optional: for selective monitoring
    tier: monitoring                 # Optional: organization
```

**Why pod labels matter:**

Network Policy example:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mysql-scrape
  namespace: robot-shop
spec:
  podSelector:
    matchLabels:
      app: mysql  # The MySQL pod itself
  
  policyTypes:
    - Ingress
  
  ingress:
    # Allow exporter to query MySQL
    - from:
        - podSelector:
            matchLabels:
              app: mysql-exporter  # ← Uses this label
      ports:
        - protocol: TCP
          port: 3306
```

---

### 4. **Metrics Exposed**

The MySQL exporter exposes ~150+ metrics. Common ones:

```
mysql_global_status_bytes_received
  → How many bytes MySQL has received total

mysql_global_status_slow_queries
  → Total slow queries (queries exceeding long_query_time)

mysql_global_status_connections
  → Total connections made

mysql_global_variables_max_connections
  → Configured max connections

mysql_up
  → 1 if exporter can connect to MySQL, 0 if not (great for alerting!)
```

---

### 5. **Complete MySQL Exporter Example**

```yaml
prometheus-mysql-exporter:
  enabled: true
  
  # Database connection
  mysql:
    host: "mysql"
    port: 3306
    user: "exporter"
    password: "exporter-password"  # Use secret in production!
    # Or reference existing secret:
    # auth:
    #   existingSecret: mysql-creds
    #   existingSecretPasswordKey: password
  
  # Prometheus discovery
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    
    # Optional: Add labels to help Prometheus filter
    labels:
      release: kube-prometheus-stack
  
  # Pod labels for network policies
  podLabels:
    app: mysql-exporter
    monitoring: enabled
  
  # Resource limits
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
  
  # Pod disruption budget (for HA scenarios)
  podDisruptionBudget:
    enabled: false
    minAvailable: 1
```

---

## Prometheus MongoDB Exporter Configuration

### 1. **Basic Configuration**

```yaml
prometheus-mongodb-exporter:
  enabled: true
  
  mongodb:
    uri: "mongodb://mongodb:27017"
    # Format: mongodb://[username:password@]host[:port]/[database][?replicaSet=name]
```

**Different connection scenarios:**

```yaml
prometheus-mongodb-exporter:
  mongodb:
    # Default (no auth)
    uri: "mongodb://mongodb:27017"
    
    # With authentication
    uri: "mongodb://exporter:exporter-password@mongodb:27017"
    
    # With external database
    uri: "mongodb://docdb.amazonaws.com:27017"
    
    # Replica set
    uri: "mongodb://member1:27017,member2:27017,member3:27017/?replicaSet=rs0"
    
    # Using secret
    auth:
      existingSecret: mongodb-exporter-secret
      existingSecretPasswordKey: mongodb-password
```

**Create MongoDB secret:**
```bash
kubectl create secret generic mongodb-exporter-secret \
  --from-literal=mongodb-password="exporter:exporter-password@mongodb:27017"
```

---

### 2. **ServiceMonitor Configuration**

```yaml
prometheus-mongodb-exporter:
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
```

**How it works (same as MySQL):**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: prometheus-mongodb-exporter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: prometheus-mongodb-exporter
  
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

---

### 3. **Pod Labels for Network Policies**

```yaml
prometheus-mongodb-exporter:
  podLabels:
    app: mongodb-exporter
    monitoring: enabled
```

**MongoDB network policy example:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mongo-scrape
  namespace: robot-shop
spec:
  podSelector:
    matchLabels:
      app: mongodb
  
  policyTypes:
    - Ingress
  
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: mongodb-exporter  # ← Uses this label
      ports:
        - protocol: TCP
          port: 27017
```

---

### 4. **Metrics Exposed**

Common MongoDB metrics:

```
mongodb_up
  → 1 if exporter can connect, 0 if not

mongodb_connections_current
  → Current number of connections

mongodb_connections_available
  → Available connections (max - current)

mongodb_database_collections
  → Number of collections per database

mongodb_instance_replication_lag_bytes
  → Replication lag (in replica sets)

mongodb_memory_resident_megabytes
  → RAM used by MongoDB

mongodb_locks_time_acquiring_global_exclusivelock_total_microseconds
  → Time spent acquiring exclusive locks (higher = contention)
```

---

### 5. **Complete MongoDB Exporter Example**

```yaml
prometheus-mongodb-exporter:
  enabled: true
  
  # Database connection
  mongodb:
    uri: "mongodb://mongodb:27017"
    # auth:
    #   existingSecret: mongodb-creds
    #   existingSecretPasswordKey: uri
  
  # Prometheus discovery
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    
    labels:
      release: kube-prometheus-stack
  
  # Pod labels
  podLabels:
    app: mongodb-exporter
    monitoring: enabled
  
  # Resource limits
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

---

## Network Policy Configuration

Your current setup uses pod labels intelligently. Here's how to expand it:

### Complete NetworkPolicy for Database Monitoring

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-monitoring
  namespace: robot-shop
spec:
  # Allow exporters to query databases
  podSelector:
    matchLabels:
      app: mysql
  
  policyTypes:
    - Ingress
  
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: mysql-exporter
      ports:
        - protocol: TCP
          port: 3306
    
    - from:
        - podSelector:
            matchLabels:
              app: mongodb-exporter
      ports:
        - protocol: TCP
          port: 27017
    
    # Allow applications to use databases normally
    - from:
        - podSelector:
            matchLabels:
              tier: application
      ports:
        - protocol: TCP
          port: 3306
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: exporter-to-prometheus
  namespace: robot-shop
spec:
  # Allow Prometheus to scrape exporters
  podSelector:
    matchLabels:
      monitoring: enabled  # Label on both exporters
  
  policyTypes:
    - Ingress
  
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: prometheus  # Prometheus pod
      ports:
        - protocol: TCP
          port: 9104  # MySQL exporter
        - protocol: TCP
          port: 9216  # MongoDB exporter
```

---

## What Each Component Actually Needs

### MySQL Exporter Requirements

```yaml
Requirements:
  ├─ MySQL Connection:
  │   ├─ Host/Port: Accessible from exporter pod
  │   ├─ User: READ-ONLY account recommended
  │   └─ Password: Stored in secret
  │
  ├─ Kubernetes Resources:
  │   ├─ Deployment or StatefulSet
  │   ├─ Service (for ServiceMonitor)
  │   ├─ ServiceMonitor CRD
  │   └─ ConfigMap (optional, for config file)
  │
  └─ Network:
      ├─ Outbound: MySQL port 3306
      └─ Inbound: Prometheus on port 9104
```

**Minimal required secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-exporter-secret
  namespace: robot-shop
type: Opaque
data:
  password: ZXhwb3J0ZXItcGFzc3dvcmQ=  # base64: exporter-password
```

### MongoDB Exporter Requirements

```yaml
Requirements:
  ├─ MongoDB Connection:
  │   ├─ URI: Connection string
  │   ├─ Auth: Username/password if needed
  │   └─ ReplicaSet: If using replica set
  │
  ├─ Kubernetes Resources:
  │   ├─ Deployment
  │   ├─ Service
  │   ├─ ServiceMonitor CRD
  │   └─ ConfigMap (optional)
  │
  └─ Network:
      ├─ Outbound: MongoDB port 27017
      └─ Inbound: Prometheus on port 9216
```

---

## Troubleshooting Guide

### Problem: "Unable to connect to MySQL"

**Checklist:**
1. Verify MySQL pod is running: `kubectl get pods -l app=mysql`
2. Test connectivity from exporter: `kubectl exec -it <exporter-pod> -- nc -zv mysql 3306`
3. Check credentials: `kubectl get secret mysql-exporter-secret -o yaml`
4. Verify NetworkPolicy allows traffic
5. Check MySQL logs: `kubectl logs -l app=mysql`

### Problem: "No data points in Prometheus"

**Steps:**
1. Verify exporter is exposing metrics: `kubectl exec -it <exporter-pod> -- curl localhost:9104/metrics`
2. Check ServiceMonitor is created: `kubectl get servicemonitor`
3. Verify Prometheus scrape target: Access Prometheus UI → Status → Targets
4. Check exporter logs: `kubectl logs <exporter-pod>`

### Problem: "ServiceMonitor not being discovered"

**Solution:**
```yaml
# In prometheus stack values, ensure:
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {}
```

Then restart Prometheus:
```bash
kubectl rollout restart statefulset/monitor-prometheus
```

---

## Best Practices

1. **Use separate users for exporters:**
   ```sql
   CREATE USER 'exporter'@'%' IDENTIFIED BY 'strong-password';
   GRANT REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
   ```

2. **Configure resource limits:**
   ```yaml
   resources:
     requests:
       cpu: 50m
       memory: 64Mi
     limits:
       cpu: 100m
       memory: 128Mi
   ```

3. **Enable network policies:**
   ```yaml
   podLabels:
     monitoring: enabled  # For network policy selectors
   ```

4. **Monitor the exporters themselves:**
   ```yaml
   # Add these alerts to AlertManager
   - alert: ExporterDown
     expr: up{job="mysql-exporter"} == 0
     for: 5m
   ```

---

## Production Checklist

- [ ] Create separate database users with minimal privileges
- [ ] Store credentials in Kubernetes Secrets
- [ ] Configure resource requests and limits
- [ ] Apply NetworkPolicy to restrict access
- [ ] Enable ServiceMonitor auto-discovery in Prometheus
- [ ] Test metrics visibility in Prometheus UI
- [ ] Add alerting rules for exporter health
- [ ] Document custom queries for team
- [ ] Set up PagerDuty integration for critical alerts
- [ ] Review exporter logs regularly

---

## Reference

- [MySQL Exporter Documentation](https://github.com/prometheus/mysqld_exporter)
- [MongoDB Exporter Documentation](https://github.com/prometheus/mongodb_exporter)
- [Helm Chart: prometheus-mysql-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-mysql-exporter)
- [Helm Chart: prometheus-mongodb-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-mongodb-exporter)
- [ServiceMonitor CRD](https://prometheus-operator.dev/docs/prometheus/latest/configuration/servicemonitor/)
