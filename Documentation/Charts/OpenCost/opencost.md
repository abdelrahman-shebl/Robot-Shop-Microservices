# OpenCost

---

## 1) What OpenCost Does

OpenCost is an open-source tool that answers: **how much does each pod, namespace, and workload actually cost?**

Cloud bills show total EC2 spend, but they do not tell you which microservice is responsible for which portion of the bill. OpenCost solves this by combining two data sources:

1. **Prometheus metrics** — real-time CPU/memory usage per pod
2. **AWS Cost & Usage Reports (CUR)** — actual dollar costs from your AWS bill

It allocates costs down to individual pods by calculating what fraction of a node's resources each pod consumes, then multiplying by the node's actual hourly cost from the CUR data.

### Why this matters for Spot instances

Spot instances have variable pricing — the same `c7i-flex.large` costs a different amount every hour depending on demand. Without CUR data, OpenCost would use on-demand list prices and significantly overestimate your spend. With CUR integration, OpenCost uses the actual spot price you paid, giving accurate cost-per-pod numbers even on mixed spot/on-demand clusters.

---

## 2) Architecture

```
  AWS Billing Service
       │
       │  writes CUR files every hour (Parquet format)
       ▼
  S3 Bucket (CUR data)
       │
       │  Glue Crawler scans and builds table schema
       ▼
  Glue Catalog Database (table definition)
       │
       │  OpenCost queries via Athena
       ▼
  Athena (serverless SQL engine)
       │
       │  query results written to
       ▼
  S3 Bucket (Athena results)
       │
       │  read by
       ▼
  OpenCost Pod (in EKS)
       │
       ├── also queries Prometheus for pod-level metrics
       │
       └── Dashboard (UI + API)
```

---

## 3) Terraform Module: Resource Breakdown

The OpenCost infrastructure module creates all the AWS-side resources needed for CUR integration.

### S3 Buckets (via community module)

```hcl
module "s3_cur" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"
  bucket  = "opencost-cur-${var.environment}-${var.bucket_suffix}"
  ...
}

module "s3_results" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"
  bucket  = "opencost-athena-results-${var.environment}-${var.bucket_suffix}"
  ...
}
```

| Bucket | Purpose |
|--------|---------|
| `s3_cur` | AWS Billing writes hourly CUR Parquet files here. A bucket policy grants the `billingreports.amazonaws.com` service write access. |
| `s3_results` | Athena writes query result files here. Temporary — safe to delete contents. |

Both use `force_destroy = true` so Terraform can clean up even with data inside (appropriate for dev/staging).

### Cost & Usage Report

```hcl
resource "aws_cur_report_definition" "opencost" {
  report_name                = "opencost-${var.environment}"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  additional_schema_elements = ["RESOURCES"]   # critical
  s3_bucket                  = module.s3_cur.s3_bucket_id
  s3_region                  = "us-east-1"     # AWS requirement
}
```

| Setting | Why |
|---------|-----|
| `time_unit = "HOURLY"` | Spot prices change hourly — daily granularity would average them out |
| `format = "Parquet"` | Columnar format that Athena queries efficiently. Smaller than CSV. |
| `additional_schema_elements = ["RESOURCES"]` | Adds EC2 instance IDs, EBS volume IDs to the report. Without this, CUR only shows service-level totals — OpenCost cannot map costs to individual nodes. |
| `s3_region = "us-east-1"` | AWS requires CUR to be created in us-east-1 regardless of your cluster region. |

### Glue Crawler

```hcl
resource "aws_glue_crawler" "opencost" {
  name          = "opencost_crawler_${var.environment}"
  database_name = aws_glue_catalog_database.opencost.name
  role          = aws_iam_role.glue_crawler.arn
  schedule      = var.crawler_schedule   # default: "cron(0 1 * * ? *)" (1 AM daily)
  ...
}
```

The Glue Crawler scans the CUR Parquet files in S3, infers the column schema, and creates/updates an Athena table automatically. The `crawler_schedule` variable controls how often it runs. CUR data updates hourly, but crawling once daily is sufficient since OpenCost caches results.

**First-time setup:** The first CUR delivery takes ~24 hours after creation. You can trigger the crawler manually after that:
```bash
aws glue start-crawler --name opencost_crawler_dev --region us-east-1
```

### Pod Identity

```hcl
resource "aws_iam_role" "opencost_pod" {
  name = "opencost-pod-role-${var.environment}"
  assume_role_policy = jsonencode({
    Statement = [{
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    = var.cluster_name
  namespace       = "opencost"
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_pod.arn
}
```

The pod role grants Athena query permissions and S3 read/write access to both buckets. EKS Pod Identity injects credentials into the pod automatically — no OIDC provider or annotation-based IRSA needed.

### Cloud Integration Secret (via SSM + ESO)

The module outputs the cloud integration JSON, which is stored in SSM by the SSM module:

```hcl
# In the SSM module:
resource "aws_ssm_parameter" "opencost_integration" {
  name  = "/prod/opencost/cloud-integration"
  type  = "SecureString"
  value = jsonencode({
    "cloud-integration.json" = var.opencost_integration_json
  })
}
```

An ExternalSecret in the `opencost` namespace pulls this from SSM and creates a Kubernetes Secret named `cloud-integration`:

```yaml
# K8s/eso/opencost-external-secrets.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: opencost-cloud-integration
  namespace: opencost
spec:
  secretStoreRef:
    name: aws-secrets
    kind: ClusterSecretStore
  target:
    name: cloud-integration
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: /prod/opencost/cloud-integration
```

The OpenCost Helm chart references this secret name via the `opencost.cloudIntegrationSecret` value.

---

## 4) Values Walkthrough

```yaml
# Cluster name injected by ArgoCD parameter override
clusterName: ""

serviceAccount:
  create: true
  name: "opencost-sa"      # must match the Pod Identity association

opencost:
  # ── Cloud Cost (CUR Integration) ─────────────────────────────────────────
  cloudCost:
    enabled: true            # enable CUR-backed cost reports
  
  cloudIntegrationSecret: "" # injected by ArgoCD: name of the K8s secret
                             # containing cloud-integration.json

  # ── Prometheus Connection ─────────────────────────────────────────────────
  prometheus:
    internal:
      enabled: false         # do NOT install a bundled Prometheus
    external:
      enabled: true
      # Point to the existing kube-prometheus-stack Prometheus service
      url: http://monitor-prometheus.monitoring.svc:80

  # ── ServiceMonitor ────────────────────────────────────────────────────────
  metrics:
    serviceMonitor:
      enabled: true          # creates a ServiceMonitor so Prometheus scrapes OpenCost

  # ── Ingress ───────────────────────────────────────────────────────────────
  ui:
    ingress:
      enabled: "true"
      ingressClassName: traefik
      annotations:
        traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
        traefik.ingress.kubernetes.io/backend-protocol: "http"
      tls:
        - secretName: opencost-tls
          hosts:
            - "opencost.yourdomain.com"
      hosts:
        - host: "opencost.yourdomain.com"
          paths:
            - "/"
```

### What gets overridden by ArgoCD parameters

In the ArgoCD Application (argo-apps-values.tpl), these values are injected dynamically:

```yaml
parameters:
  - name: "clusterName"
    value: "${cluster_name}"
  - name: "opencost.cloudIntegrationSecret"
    value: "${cloudIntegrationSecret}"   # "cloud-integration"
  - name: "opencost.ui.ingress.hosts[0].host"
    value: "opencost.${domain}"
  - name: "opencost.ui.ingress.tls[0].hosts[0]"
    value: "opencost.${domain}"
```

---

## 5) How OpenCost Handles Spot Pricing

This is where CUR integration becomes essential.

### Without CUR (metrics-only mode)

OpenCost uses the on-demand list price for each instance type. A `c7i-flex.large` is always priced at the on-demand rate (~$0.0504/hr). If the node is actually a Spot instance paying $0.015/hr, OpenCost overestimates the cost by 3x.

### With CUR (cloud-cost mode)

OpenCost queries the CUR data via Athena:

```sql
SELECT line_item_resource_id, line_item_unblended_cost, pricing_term
FROM opencost_db.opencost
WHERE line_item_resource_id = 'i-0abc123...'
  AND line_item_usage_start_date >= '2026-02-25'
```

This returns the **actual cost billed by AWS** for each EC2 instance, which for Spot includes the real-time Spot price at each hour. OpenCost then distributes that actual node cost across the pods running on it, proportionally by their CPU/memory usage.

### The `RESOURCES` schema element

The `additional_schema_elements = ["RESOURCES"]` setting in the CUR definition is what makes per-node cost attribution possible. It adds the `line_item_resource_id` column — the EC2 instance ID. Without it, CUR only shows "EC2: $500/day" with no way to know which instance contributed what amount.

---

## 6) Module Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `cluster_name` | (required) | EKS cluster name for Pod Identity association |
| `environment` | `"dev"` | Appended to resource names for multi-env isolation |
| `bucket_suffix` | `"0022"` | Ensures globally unique S3 bucket names |
| `crawler_schedule` | `"cron(0 1 * * ? *)"` | How often Glue re-crawls CUR data (1 AM daily) |
| `tags` | `{}` | AWS tags applied to all resources |

---

## 7) Useful Commands

```bash
# Check OpenCost pod is running and has cloud credentials
kubectl get pods -n opencost
kubectl describe pod -n opencost -l app.kubernetes.io/name=opencost

# Verify the cloud-integration secret exists
kubectl get secret cloud-integration -n opencost -o jsonpath='{.data.cloud-integration\.json}' | base64 -d | jq .

# Trigger crawler manually (first time or after CUR schema change)
aws glue start-crawler --name opencost_crawler_dev --region us-east-1

# Check crawler status
aws glue get-crawler --name opencost_crawler_dev --region us-east-1 --query 'Crawler.State'

# Query CUR data directly via Athena (debugging)
aws athena start-query-execution \
  --query-string "SELECT * FROM opencost_db_dev.opencost_dev LIMIT 10" \
  --result-configuration "OutputLocation=s3://opencost-athena-results-dev-0022/"
```
