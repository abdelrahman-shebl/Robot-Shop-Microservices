# Terraform Files - Updated Configuration

## Location: `terrafrom/modules/karpenter/main.tf`

This file defines the Karpenter node orchestration system, including:
- EC2NodeClass: Defines AWS EC2 instance configuration
- NodePool: Defines Kubernetes node pool with resource limits and requirements

### Complete Updated File:

```terraform
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version = "1.8.1"

  namespace  = "karpenter"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/karpenter-values.tpl", {
      cluster_name   = var.cluster_name
      queue_name     = var.queue_name
    })
  ]
}


resource "kubectl_manifest" "karpenter_node_class" {
  
  yaml_body = <<-YAML
      apiVersion: karpenter.k8s.aws/v1
      kind: EC2NodeClass
      metadata:
        name: default
      spec:

        role: "${var.karpenter_role}"

        subnetSelectorTerms:
          - tags:
              karpenter.sh/discovery: "${var.cluster_name}"

        securityGroupSelectorTerms:
          - tags:
              karpenter.sh/discovery: "${var.cluster_name}"


        amiFamily: AL2023

        blockDeviceMappings:
          - deviceName: /dev/xvda
            ebs:
              volumeSize: 100Gi
              volumeType: gp3
              encrypted: true

  YAML

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:

      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]

            - key: node.kubernetes.io/instance-type 
              operator: In
              values: 
                - "t3.medium"      # Baseline: 1 vCPU, 4GB RAM
                - "t3.large"       # Better baseline: 2 vCPU, 8GB RAM
                - "c7i-flex.large" # Compute optimized: 2 vCPU, 8GB RAM
                - "m7i-flex.large" # Memory optimized: 2 vCPU, 8GB RAM

      limits:
        cpu: 50
        memory: 200Gi

      disruption:

        consolidationPolicy: WhenEmptyOrUnderutilized
        
        consolidateAfter: 300s
        
        expireAfter: 168h
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
```

### Key Changes Explained:

#### 1. EC2NodeClass Changes

**Root Volume Size:**
```terraform
# BEFORE (20Gi)
volumeSize: 20Gi

# AFTER (100Gi) - 5x increase
volumeSize: 100Gi
```
**Why**: Container images (Prometheus, Grafana, PostgreSQL) are 500MB+ each. A 20GB volume fills up quickly.

---

#### 2. NodePool Changes

**Instance Types:**
```terraform
# BEFORE (t3.small only)
values: 
  - "t3.small"       # ❌ Only 1 vCPU, 2GB
  - "c7i-flex.large"
  - "m7i-flex.large"

# AFTER (better sizing)
values: 
  - "t3.medium"      # ✅ 1 vCPU, 4GB
  - "t3.large"       # ✅ 2 vCPU, 8GB
  - "c7i-flex.large" # 2 vCPU, 8GB
  - "m7i-flex.large" # 2 vCPU, 8GB
```
**Why**: t3.small is too small - a single pod could consume entire node. Need baseline capacity.

---

**Cluster Limits:**
```terraform
# BEFORE (Severely under-resourced)
limits:
  cpu: 10
  memory: 40Gi

# AFTER (5x increase to support workload)
limits:
  cpu: 50
  memory: 200Gi
```
**Why**: Running 50+ pods (ArgoCD, Prometheus, Grafana, DefectDojo, MongoDB, MySQL, Traefik, etc.) requires 50+ CPUs and 200GB+.

---

**Consolidation Policy:**
```terraform
# BEFORE (❌ Invalid enum)
consolidationPolicy: WhenUnderutilized

# AFTER (✅ Valid enum)
consolidationPolicy: WhenEmptyOrUnderutilized
```
**Why**: `WhenUnderutilized` is not valid. Valid options are: `WhenEmpty`, `WhenEmptyOrUnderutilized`, `Disabled`.

---

**Consolidation Timing:**
```terraform
# BEFORE (Aggressive - pod disruptions every 30s)
consolidateAfter: 30s

# AFTER (Reasonable - every 5 minutes)
consolidateAfter: 300s
```
**Why**: 30 seconds is too aggressive, causing constant pod evictions and rescheduling. 5 minutes allows services to stabilize.

---

---

## Location: `terrafrom/modules/addons/values/traefik-values.yaml`

This file configures the Traefik ingress controller.

### Complete Updated File:

```yaml
ports:
  web:
    port: 8000
  websecure:
    port: 8443

service:
  enabled: true
  type: LoadBalancer

additionalArguments:
  - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
  - "--certificatesresolvers.letsencrypt.acme.email=sheblabdo00@gmail.com"
  - "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json"

persistence:
  enabled: false
```

### Change Explained:

**Persistence Configuration:**
```yaml
# BEFORE (Caused FailedScheduling)
persistence:
  enabled: true
  path: /data
  size: 128Mi
  storageClassName: gp2  # Added but still pending

# AFTER (Disabled to resolve PVC binding)
persistence:
  enabled: false
```

**Why**: 
- Traefik PVC was pending because StorageClass wasn't properly bound
- With `WaitForFirstConsumer` VolumeBindingMode, PVC binding requires a pod to request it
- Disabling persistence allows Traefik to start immediately
- ACME certificates stored in /data can be stored as ConfigMap/Secret instead
- For production: Re-enable with properly configured PersistentVolume or StorageClass

---

---

## Location: `terrafrom/modules/addons/values/argo-apps-values.tpl`

This file defines all ArgoCD applications (12 total).

### Key Changes:

#### 1. External Secrets Operator

```yaml
# BEFORE (Chart not found)
external-secrets-operator:
  sources:
    - chart: external-secrets
      repoURL: https://charts.external-secrets.io/
      targetRevision: "1.3.2"  # ❌ Not available

# AFTER (Valid version)
external-secrets-operator:
  sources:
    - chart: external-secrets
      repoURL: https://charts.external-secrets.io/
      targetRevision: "0.12.1"  # ✅ Available stable version
```

---

#### 2. Kube-Prometheus-Stack Registry Migration

```yaml
# BEFORE (OCI Registry - 403 Forbidden)
kube-prometheus-stack:
  sources:
    - chart: kube-prometheus-stack
      repoURL: oci://ghcr.io/prometheus-community/charts  # ❌ OCI auth failed
      targetRevision: "68.2.2"

# AFTER (Helm Repository)
kube-prometheus-stack:
  sources:
    - chart: kube-prometheus-stack
      repoURL: https://prometheus-community.github.io/helm-charts  # ✅ Standard Helm
      targetRevision: "68.2.2"
```

---

#### 3. Ingress Parameter Structure Fixes

**Before (Incorrect format):**
```yaml
opencost:
  parameters:
    - name: "opencost.ui.ingress.hosts[0]"
      value: "opencost.shebl22.me"
    # ❌ Missing .host, .path, .pathType structure
```

**After (Correct structure):**
```yaml
opencost:
  parameters:
    - name: "opencost.ui.ingress.hosts[0].host"
      value: "opencost.shebl22.me"
    - name: "opencost.ui.ingress.hosts[0].paths[0]"
      value: "/"
    - name: "opencost.ui.ingress.hosts[0].paths[0].pathType"
      value: "Prefix"
    - name: "opencost.ui.ingress.tls[0].hosts[0]"
      value: "opencost.shebl22.me"
```

---

---

## Location: `K8s/eso/` - External Secrets Manifests

These files configure AWS Secrets Manager integration.

### File 1: `SecretStore.yaml`

**Before:**
```yaml
apiVersion: external-secrets.io/v1  # ❌ Not supported
kind: ClusterSecretStore
metadata:
  name: aws-secrets
spec:
  provider:
    aws:
      service: ParameterStore  
      region: eu-north-1  # ❌ Wrong region
```

**After:**
```yaml
apiVersion: external-secrets.io/v1beta1  # ✅ Supported API version
kind: ClusterSecretStore 
metadata:
  name: aws-secrets
spec:
  provider:
    aws:
      service: ParameterStore  
      region: us-east-1  # ✅ Correct region
```

---

### File 2: `mysql-external-secrets.yaml`

**Before:**
```yaml
apiVersion: external-secrets.io/v1  # ❌ Wrong version
kind: ExternalSecret
metadata:
  name: db-secrets-mapping  # ❌ Generic name (duplicate with mongo)
  namespace: robotshop
```

**After:**
```yaml
apiVersion: external-secrets.io/v1beta1  # ✅ Correct version
kind: ExternalSecret
metadata:
  name: mysql-secrets-mapping  # ✅ Unique name
  namespace: robotshop
```

---

### File 3: `mongo-external-secrets.yaml`

**Before:**
```yaml
apiVersion: external-secrets.io/v1  # ❌ Wrong version
kind: ExternalSecret
metadata:
  name: db-secrets-mapping  # ❌ Duplicate (same as mysql)
  namespace: robotshop
```

**After:**
```yaml
apiVersion: external-secrets.io/v1beta1  # ✅ Correct version
kind: ExternalSecret
metadata:
  name: mongo-secrets-mapping  # ✅ Unique name
  namespace: robotshop
```

---

### File 4: `dojo-external-secrets.yaml`

**Before:**
```yaml
apiVersion: external-secrets.io/v1  # ❌ Wrong version
kind: ExternalSecret
metadata:
  name: db-secrets-mapping  # ❌ Duplicate name
  namespace: dojo
```

**After:**
```yaml
apiVersion: external-secrets.io/v1beta1  # ✅ Correct version
kind: ExternalSecret
metadata:
  name: dojo-secrets-mapping  # ✅ Unique name
  namespace: dojo
```

---

---

## Summary of All Changes

| File | Change | Before | After | Impact |
|------|--------|--------|-------|--------|
| `karpenter/main.tf` | Node Volume | 20Gi | 100Gi | Prevents image cache overflow |
| `karpenter/main.tf` | Instance Default | t3.small | t3.medium/large | Adequate node capacity |
| `karpenter/main.tf` | CPU Limit | 10 | 50 | 5x cluster capacity |
| `karpenter/main.tf` | Memory Limit | 40Gi | 200Gi | 5x cluster capacity |
| `karpenter/main.tf` | Consolidation Policy | WhenUnderutilized | WhenEmptyOrUnderutilized | Valid API enum |
| `karpenter/main.tf` | Consolidation Timing | 30s | 300s | Reduces pod disruptions |
| `traefik-values.yaml` | Persistence | enabled: true | enabled: false | Resolves PVC binding |
| `argo-apps-values.tpl` | ESO Version | 1.3.2 | 0.12.1 | Chart availability |
| `argo-apps-values.tpl` | Prometheus Repo | oci://ghcr.io | https://prometheus-community | OCI auth issue |
| `argo-apps-values.tpl` | Ingress Format | hosts[0].host | hosts[0].path etc. | Helm schema compliance |
| `K8s/eso/*.yaml` | API Version | v1 | v1beta1 | Cluster compatibility |
| `K8s/eso/*.yaml` | Resource Names | db-secrets-mapping | *-secrets-mapping | Unique identifiers |
| `K8s/eso/SecretStore.yaml` | AWS Region | eu-north-1 | us-east-1 | Correct parameter store location |

---

## Git Commits

All changes have been committed to `feature/pipeline` branch:

```bash
# Commit: 02e04df
Fix Karpenter: incorrect consolidationPolicy, insufficient limits, and small instance types

# Commit: 43e9004
Disable Traefik persistence for now

# Commit: ab6eeec
Fix ESO API version to v1beta1 and add Traefik storage class

# Commit: 6bd8408
Fix ArgoCD app values and ESO store

# Commit: 6c3be5e
Fix ESO duplicates, region, and chart values
```

---

## How to Apply These Changes

### Option 1: Terraform (Recommended for IaC)
```bash
cd terrafrom
terraform plan  # Review changes
terraform apply # Apply changes
```

### Option 2: Manual kubectl
```bash
# Update Karpenter NodePool
kubectl patch nodepool default --type merge -p '{
  "spec": {
    "limits": {"cpu": 50, "memory": "200Gi"},
    "disruption": {"consolidateAfter": "300s"}
  }
}'

# Update Traefik
helm upgrade traefik traefik/traefik -n traefik \
  --set persistence.enabled=false
```

---

## Verification

```bash
# Check Karpenter configuration
kubectl get nodepool default -o yaml

# Check if pods are running
kubectl get pods -A | grep -E "Running|Pending"

# Check Traefik
kubectl get pods -n traefik

# Check External Secrets
kubectl get externalsecrets -A
```

---

**Last Updated**: February 12, 2026  
**Status**: All fixes applied and validated
