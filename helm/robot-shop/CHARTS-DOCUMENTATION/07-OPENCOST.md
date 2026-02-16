# OpenCost - Complete Guide

## Overview

OpenCost provides real-time visibility into Kubernetes cluster costs. It breaks down costs by namespace, pod, deployment, and even individual containers, integrating with cloud provider billing data (AWS, Azure, GCP).

**What OpenCost solves:**
```
Problem: "How much is our Kubernetes cluster costing?"
Before OpenCost:
├─ AWS bill arrives end of month
├─ Total: $5000 - unsure what caused it
├─ Kubernetes team: "Blame DevOps"
├─ DevOps team: "Blame developers"
└─ No visibility, no optimization

With OpenCost:
├─ Real-time dashboard
├─ Namespace costs: payment-service = $1200/month
├─ Pod costs: db-backup job = $300/month
├─ Cost breakdown: compute 60%, storage 30%, networking 10%
├─ Optimization: "Kill unused VMs" → save 40%
└─ Data-driven cost decisions
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  OpenCost Pod (Runs in cluster)                     │
│  ┌──────────────────────────────────────────────────┐
│  │ Prometheus scraper module                        │
│  │ - Queries Prometheus for metrics                 │
│  │ - CPU, memory, storage usage per pod             │
│  │ - Node resource allocation                       │
│  └──────────────────────────────────────────────────┘
│                 ↓
│  ┌──────────────────────────────────────────────────┐
│  │ Cloud cost module                                │
│  │ - Queries AWS Pricing API                        │
│  │ - Gets current EC2 instance prices               │
│  │ - Spot vs on-demand rates                        │
│  │ - EBS, data transfer pricing                     │
│  └──────────────────────────────────────────────────┘
│                 ↓
│  ┌──────────────────────────────────────────────────┐
│  │ Allocation engine                                │
│  │ - Maps metrics to costs                          │
│  │ - Allocates shared resources (nodes, networking) │
│  │ - Calculates per-namespace/pod/container costs  │
│  └──────────────────────────────────────────────────┘
│                 ↓
│  ┌──────────────────────────────────────────────────┐
│  │ API & UI                                         │
│  │ - REST API for cost queries                      │
│  │ - Web dashboard (Grafana-like)                   │
│  │ - Kubernetes-native views                        │
│  └──────────────────────────────────────────────────┘
└──────────────────────────────────────────────────────┘
         ↓ Queries                  ↑ Integration
┌─────────────────────┐    ┌──────────────────────┐
│   Prometheus        │    │  AWS Cost Explorer   │
│   (Metrics)         │    │  (Actual billing)    │
└─────────────────────┘    └──────────────────────┘
```

---

## Helm Chart Configuration

### 1. **Basic Enable**

```yaml
opencost:
  enabled: true
  clusterName: "cluster.local"  # Cluster identifier
  # Use your actual cluster name in production
```

---

### 2. **Cloud Cost Integration**

```yaml
opencost:
  opencost:
    cloudCost:
      enabled: true
      # Enables AWS cloud cost data integration
      # Reconciles Kubernetes metrics with AWS billing
```

**What cloud cost integration does:**

```
Without cloud cost (metrics-only):
Kubernetes says: "Pod X uses 2 GB RAM"
OpenCost: "Allocate 2 GB price = $0.20/day"
Problem: Doesn't match AWS bill ($0.15/day)

With cloud cost (integrated):
Kubernetes says: "Pod X uses 2 GB RAM"
AWS says: "Instance price = $0.20/day"
OpenCost: "Maps RAM to instance price" = $0.20/day
Result: Matches AWS bill exactly!
```

---

### 3. **Cloud Integration Secret**

```yaml
opencost:
  opencost:
    cloudIntegrationSecret: "cloud-integration"
    # Secret containing AWS credentials/configuration
```

**Creating the secret:**

```bash
# Option 1: AWS Spot Data pricing (for accurate spot prices)
kubectl create secret generic cloud-integration \
  --from-literal=SPOT_DATA_FEED_ACCOUNT="<AWS-account-ID>" \
  --from-literal=SPOT_DATA_FEED_BUCKET="s3://my-spot-prices/" \
  --from-literal=SPOT_DATA_FEED_PREFIX="spot-prices/"

# Option 2: Public Spot API (simpler, less accurate)
# Don't need secret, OpenCost uses public API

# Option 3: Using AWS credentials
kubectl create secret generic cloud-integration \
  --from-literal=AWS_ACCESS_KEY_ID="<key>" \
  --from-literal=AWS_SECRET_ACCESS_KEY="<secret>" \
  --from-literal=AWS_REGION="us-east-1"
```

---

### 4. **Prometheus Connection (CRITICAL)**

```yaml
opencost:
  opencost:
    prometheus:
      internal:
        enabled: false  # Don't install new Prometheus
      external:
        enabled: true
        # CRITICAL: Point to existing Prometheus
        url: "http://prom-monitor-prometheus.monitoring.svc:80"
        # Format: http://<service-name>.<namespace>.svc:<port>
```

**Why URL format matters:**

```yaml
# ❌ Wrong - won't work
url: "prometheus:9090"
# Can't find service outside namespace

# ❌ Wrong - incomplete
url: "prom-monitor-prometheus"
# Missing namespace and port

# ✅ Correct - full Kubernetes DNS
url: "http://prom-monitor-prometheus.monitoring.svc:80"
# service-name.namespace.svc.cluster.local:port
# (cluster.local is default, can be omitted if in same DNS)

# ✅ Also correct (if OpenCost in same namespace as Prometheus)
url: "http://prom-monitor-prometheus:80"
```

**Easier approach with separate values:**

```yaml
# Instead of hardcoding URL, use templating
prometheus:
  serviceName: "monitor-prometheus"
  namespace: "monitoring"
  port: 80

# In OpenCost config:
url: "http://{{ .Values.prometheus.serviceName }}.{{ .Values.prometheus.namespace }}.svc:{{ .Values.prometheus.port }}"
```

---

### 5. **ServiceAccount**

```yaml
opencost:
  opencost:
    serviceAccount:
      create: true
      name: "opencost-sa"
```

---

### 6. **Cloud Integration for AWS**

#### Getting Spot Instance Pricing

```yaml
opencost:
  opencost:
    cloudCost:
      enabled: true
    
    # For accurate spot pricing (vs on-demand):
    SPOT_DATA_FEED_ENABLED: "true"
    SPOT_DATA_FEED_ACCOUNT: "123456789012"  # Your AWS account
    SPOT_DATA_FEED_BUCKET: "s3://my-bucket/spot-data/"
    SPOT_DATA_FEED_PREFIX: "DescribeSpotPriceHistory/"
```

**Spot Data Feed Requirements:**

```hcl
# In Terraform, create S3 bucket for spot data
resource "aws_s3_bucket" "spot_data" {
  bucket = "my-spot-data-bucket"
}

resource "aws_s3_bucket_versioning" "spot_data" {
  bucket = aws_s3_bucket.spot_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure AWS to deliver spot pricing to this bucket
# This is done in AWS console or via CLI:
aws ec2 create-spot-datafeed-subscription \
  --bucket my-spot-data-bucket \
  --prefix DescribeSpotPriceHistory/
```

**Important: Bucket setup takes 24 hours**

```
Day 1:
- Create S3 bucket
- Configure spot data feed
- OpenCost status: "Waiting for data"

Day 2:
- AWS starts delivering spot prices to bucket
- OpenCost reads bucket
- Now has accurate spot pricing

Timeline: 24-hour wait before spot pricing available!
```

---

### 7. **UI Configuration (Ingress)**

```yaml
opencost:
  opencost:
    ui:
      ingress:
        enabled: "true"
        ingressClassName: traefik
        
        hosts:
        - host: opencost.yourdomain.com
        
        tls: 
           - secretName: opencost-tls
             hosts:
               - opencost.yourdomain.com
```

---

## AWS Infrastructure Setup - Complete Guide

OpenCost can work in **two modes** for AWS cost tracking:

### Mode 1: Simple API-Based (Quick Start)
- Uses AWS Pricing API for on-demand prices
- Less accurate for Spot instances
- No AWS infrastructure needed
- Good for proof-of-concept

### Mode 2: CUR + Athena Integration (Production)
- Uses actual AWS billing data (Cost & Usage Reports)
- 100% accurate costs matching your AWS bill
- Requires AWS infrastructure setup
- Recommended for production

**We'll focus on Mode 2 (CUR + Athena) as it's production-ready.**

---

## Complete Terraform Configuration (No Modules)

The Terraform file in `charts/opencost/opencost.tf` creates all required AWS resources. Here's what each section does:

### Architecture Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                   AWS BILLING SYSTEM                             │
│  Generates hourly cost data for all AWS resources               │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  1. COST & USAGE REPORT (CUR)                                    │
│     - Exports billing data to S3                                 │
│     - Format: Parquet (10x faster than CSV)                      │
│     - Includes resource IDs (EC2 instance tags)                  │
│     - Hourly granularity (for accurate Spot pricing)             │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  2. S3 BUCKET (opencost_cur)                                     │
│     - Stores billing Parquet files                               │
│     - Path: s3://bucket/cur/opencost/opencost/year=2024/month=02/│
│     - Updated hourly by AWS Billing Service                      │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  3. GLUE CRAWLER                                                 │
│     - Scans S3 bucket                                            │
│     - Infers Parquet schema automatically                        │
│     - Creates/updates Athena table                               │
│     - Runs manually first time, then weekly                      │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  4. GLUE DATABASE & ATHENA TABLE                                 │
│     - Database: opencost_db                                      │
│     - Table: opencost (auto-created by crawler)                  │
│     - Schema: 100+ columns (cost, resource_id, tags, etc.)      │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  5. OPENCOST POD (Kubernetes)                                    │
│     - Queries Athena: "SELECT cost WHERE pod='nginx'"            │
│     - Uses Pod Identity for authentication                       │
│     - Writes results to opencost_results bucket                  │
│     - Displays costs in dashboard                                │
└────────────────────────┬─────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  6. S3 BUCKET (opencost_results)                                 │
│     - Stores Athena query results                                │
│     - Temporary files (can auto-delete after 7 days)             │
│     - Small files (<1MB per query)                               │
└──────────────────────────────────────────────────────────────────┘
```

---

## Section-by-Section Terraform Explanation

### **Section 1: S3 Bucket for CUR Data**

```hcl
resource "aws_s3_bucket" "opencost_cur" {
  bucket        = "my-company-billing-data-storage-001"
  force_destroy = true
}
```

**What it does:**
- Creates primary storage for AWS billing exports
- AWS writes Parquet files here every hour
- Files contain ALL AWS costs (EC2, EBS, S3, data transfer, etc.)

**Naming convention:**
```
Path structure created by AWS:
s3://my-company-billing-data-storage-001/
  └── cur/                          # Your s3_prefix
      └── opencost/                 # Your report_name
          └── opencost/             # Report versioning folder
              ├── year=2024/
              │   ├── month=01/
              │   │   ├── day=15/
              │   │   │   └── data-00001.snappy.parquet
              │   │   └── day=16/
              │   └── month=02/
              └── manifest.json
```

**Cost:** ~$3-5/month for 150GB of billing data

---

### **Section 2: S3 Bucket Policy**

```hcl
resource "aws_s3_bucket_policy" "opencost_cur_policy" {
  bucket = aws_s3_bucket.opencost_cur.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCURWrite"
      Effect    = "Allow"
      Principal = { Service = "billingreports.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:PutObject"]
      Resource  = [
        aws_s3_bucket.opencost_cur.arn,
        "${aws_s3_bucket.opencost_cur.arn}/*"
      ]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
```

**What it does:**
- Grants AWS Billing Service permission to write to your bucket
- **Critical:** Without this policy, CUR delivery fails silently

**Why the Condition?**
- Security best practice: only YOUR account can write billing data
- Prevents potential attacks where someone writes fake billing data to your bucket

**How AWS uses it:**
1. AWS Billing Service checks: `s3:GetBucketAcl` (verifies permissions)
2. Then writes files: `s3:PutObject` (delivers billing Parquet files)

---

### **Section 3: Cost & Usage Report Definition**

```hcl
resource "aws_cur_report_definition" "opencost" {
  report_name                = "opencost"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.opencost_cur.id
  s3_region                  = "us-east-1"
  s3_prefix                  = "cur"
  report_versioning          = "OVERWRITE_REPORT"
}
```

**Critical settings explained:**

#### `time_unit = "HOURLY"`
**Why hourly matters:**
```
Example: Spot instance terminated mid-hour

DAILY granularity:
- Instance runs 10 minutes
- AWS charges: $0.05
- CUR shows: $1.20 (full day)
- OpenCost: "This pod cost $1.20 today" ❌ WRONG

HOURLY granularity:
- Instance runs 10 minutes (0.17 hours)
- AWS charges: $0.05
- CUR shows: $0.05 (partial hour)
- OpenCost: "This pod cost $0.05 today" ✅ CORRECT
```

#### `format = "Parquet"`
**Why Parquet vs CSV:**
```
Same billing data (1 month):

CSV format:
- File size: 10 GB
- Athena scans: 10 GB per query
- Query cost: $0.05/query ($5/TB × 10GB)
- Query time: 30 seconds

Parquet format:
- File size: 3 GB (70% smaller)
- Athena scans: 0.5 GB per query (columnar, only reads needed columns)
- Query cost: $0.0025/query ($5/TB × 0.5GB)
- Query time: 3 seconds

Savings: 20x cheaper + 10x faster
```

#### `additional_schema_elements = ["RESOURCES"]`
**The most critical setting:**
```
WITHOUT "RESOURCES":
CUR output:
┌────────────────┬───────────┬────────┐
│ Service        │ Cost      │ Date   │
├────────────────┼───────────┼────────┤
│ EC2-Instances  │ $150.00   │ Feb 01 │
│ EBS-Volumes    │ $50.00    │ Feb 01 │
└────────────────┴───────────┴────────┘

OpenCost shows:
- "EC2 costs: $150" (useless, which pods?)

WITH "RESOURCES":
CUR output:
┌────────────────┬───────────┬────────┬──────────────────────────┐
│ Service        │ Cost      │ Date   │ Resource ID              │
├────────────────┼───────────┼────────┼──────────────────────────┤
│ EC2-Instances  │ $75.00    │ Feb 01 │ i-abc123 (tag:pod=nginx) │
│ EC2-Instances  │ $50.00    │ Feb 01 │ i-def456 (tag:pod=redis) │
│ EC2-Instances  │ $25.00    │ Feb 01 │ i-ghi789 (tag:pod=db)    │
└────────────────┴───────────┴────────┴──────────────────────────┘

OpenCost shows:
- "nginx pod: $75"
- "redis pod: $50"
- "db pod: $25"
```

**How it works:**
1. Kubernetes tags EC2 nodes with pod names
2. CUR exports these tags when RESOURCES enabled
3. OpenCost matches pod → node → cost

---

### **Section 4: Athena Results Bucket**

```hcl
resource "aws_s3_bucket" "opencost_results" {
  bucket        = "my-company-opencost-athena-results-001"
  force_destroy = true
}
```

**What it does:**
- Temporary storage for Athena query outputs
- Athena CANNOT return results directly - must write to S3

**How Athena uses it:**
```
Query flow:
1. OpenCost: "SELECT cost FROM opencost_db.opencost WHERE pod='nginx'"
2. Athena: Scans Parquet files in opencost_cur bucket
3. Athena: Writes results to THIS bucket as CSV
4. OpenCost: Reads CSV from this bucket
5. OpenCost: Displays "$75" in dashboard

Result files auto-accumulate (add lifecycle policy to delete after 7 days):
s3://opencost-results/
  ├── query-abc123.csv (10 KB)
  ├── query-def456.csv (15 KB)
  └── query-ghi789.csv (12 KB)
```

**Cost:** ~$0.50/month (small files)

---

### **Section 5: Glue Database & Crawler**

```hcl
resource "aws_glue_catalog_database" "opencost" {
  name = "opencost_db"
}

resource "aws_glue_crawler" "opencost" {
  name          = "opencost_crawler"
  database_name = aws_glue_catalog_database.opencost.name
  role          = aws_iam_role.glue_crawler.arn
  
  s3_target {
    path = "s3://${aws_s3_bucket.opencost_cur.bucket}/cur/opencost/opencost/"
  }
}
```

**What Glue Crawler does:**
- **Problem:** CUR Parquet files have 100+ columns with nested structs
- **Solution:** Crawler auto-discovers schema and creates Athena table

**Crawler workflow:**
```
Step 1: You run crawler (first time manual)
  aws glue start-crawler --name opencost_crawler

Step 2: Crawler scans S3 path
  - Reads sample Parquet files
  - Analyzes schema: column names, data types, nested structures

Step 3: Crawler creates Athena table
  CREATE TABLE opencost_db.opencost (
    identity_line_item_id STRING,
    line_item_usage_account_id STRING,
    line_item_line_item_type STRING,
    line_item_usage_start_date TIMESTAMP,
    line_item_product_code STRING,
    line_item_unblended_cost DOUBLE,
    resource_tags_user_name STRING,
    ... (100+ more columns)
  )
  PARTITIONED BY (year INT, month INT)
  STORED AS PARQUET

Step 4: OpenCost can now query
  SELECT 
    line_item_unblended_cost,
    resource_tags_user_name
  FROM opencost_db.opencost
  WHERE resource_tags_user_name LIKE '%nginx%'
```

**Schedule:** Run manually after first CUR delivery (24 hours), then weekly

---

### **Section 6: IAM Permissions - Glue Crawler**

```hcl
resource "aws_iam_role" "glue_crawler" {
  name = "opencost-glue-crawler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "glue-s3-access"
  role = aws_iam_role.glue_crawler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = ["${aws_s3_bucket.opencost_cur.arn}/*"]
    }]
  })
}
```

**What each policy does:**

1. **Trust Policy** (who can use this role):
   - Allows `glue.amazonaws.com` to assume role
   - Only Glue service can use these permissions

2. **AWSGlueServiceRole** (AWS managed policy):
   - Includes: `glue:CreateTable`, `glue:UpdateTable`, `glue:GetDatabase`
   - Allows crawler to write table schema to Glue Catalog
   - Includes CloudWatch Logs permissions for debugging

3. **Custom S3 Policy**:
   - `s3:GetObject`: Read Parquet files to infer schema
   - `s3:PutObject`: Not strictly needed, but useful for debugging

---

### **Section 7: IAM Permissions - OpenCost Pod**

```hcl
resource "aws_iam_role" "opencost_pod" {
  name = "OpenCostPodRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "opencost_access" {
  name = "opencost-access"
  role = aws_iam_role.opencost_pod.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:*",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:GetDatabase"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.opencost_cur.arn,
          "${aws_s3_bucket.opencost_cur.arn}/*",
          aws_s3_bucket.opencost_results.arn,
          "${aws_s3_bucket.opencost_results.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "opencost"
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_pod.arn
}
```

**Permission breakdown:**

#### **Athena Permissions:**
```
athena:StartQueryExecution  → Run SQL queries
athena:GetQueryExecution    → Check query status
athena:GetQueryResults      → Fetch results
athena:StopQueryExecution   → Cancel queries
```

#### **Glue Permissions:**
```
glue:GetTable      → Read table schema
glue:GetPartitions → Read partition info (year=2024/month=02)
glue:GetDatabase   → Read database metadata
```

#### **S3 Permissions:**
```
For CUR bucket (READ):
  s3:GetObject         → Read Parquet files during queries
  s3:ListBucket        → List available files
  s3:GetBucketLocation → Find bucket region

For Results bucket (READ + WRITE):
  s3:PutObject                   → Write query results
  s3:ListBucketMultipartUploads  → Manage large uploads
  s3:AbortMultipartUpload        → Cancel failed uploads
```

#### **Pod Identity Association:**
**How it works:**
```
1. You create ServiceAccount in Kubernetes:
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: opencost-sa
     namespace: opencost

2. You apply Pod Identity Association (Terraform resource above)
   Links: namespace=opencost + sa=opencost-sa → IAM role

3. OpenCost pod starts with:
   spec:
     serviceAccountName: opencost-sa

4. EKS Pod Identity Agent (DaemonSet) detects pod

5. Agent injects credentials:
   Environment variables:
   - AWS_ROLE_ARN=arn:aws:iam::123:role/OpenCostPodRole
   - AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/...
   
   Credentials auto-rotate every 15 minutes

6. OpenCost AWS SDK automatically uses credentials
   No code changes needed!
```

---

## Why No Terraform Modules?

**Modules hide critical configuration:**

```hcl
# ❌ Using a module (what you DON'T see):
module "opencost" {
  source = "some-module"
  bucket_name = "my-bucket"
}

# What's hidden:
# - Is time_unit HOURLY or DAILY?
# - Is format Parquet or CSV?
# - Are RESOURCES enabled?
# - What IAM permissions are granted?
# - Is there a security Condition?

Result: You trust the module, but OpenCost doesn't work correctly


# ✅ Explicit resources (what you DO see):
resource "aws_cur_report_definition" "opencost" {
  time_unit = "HOURLY"  # You see this
  format    = "Parquet" # You see this
  additional_schema_elements = ["RESOURCES"]  # You see this
}

Result: Full transparency, easy debugging
```

---

## Terraform Output - cloud-integration.json

After running `terraform apply`, you get this output:

```hcl
output "OPENCOST_CONFIG" {
  value = {
    projectID        = "123456789012"
    athenaBucketName = "my-company-opencost-athena-results-001"
    athenaDatabase   = "opencost_db"
    athenaTable      = "opencost"
    athenaRegion     = "us-east-1"
  }
}
```

**How to use this output:**

```bash
# Step 1: Get output as JSON
terraform output -json OPENCOST_CONFIG | jq > /tmp/cloud-integration.json

# Step 2: Wrap in required format for OpenCost
cat /tmp/cloud-integration.json
# Should show:
{
  "projectID": "123456789012",
  "athenaBucketName": "my-company-opencost-athena-results-001",
  "athenaDatabase": "opencost_db",
  "athenaTable": "opencost",
  "athenaRegion": "us-east-1"
}

# Step 3: Create Kubernetes secret
kubectl create namespace opencost
kubectl create secret generic cloud-integration \
  --from-file=cloud-integration.json=/tmp/cloud-integration.json \
  -n opencost

# Step 4: Verify secret created
kubectl get secret cloud-integration -n opencost -o yaml
```

**What each field means:**

| Field | Value | Explanation |
|-------|-------|-------------|
| `projectID` | 123456789012 | Your AWS account ID |
| `athenaBucketName` | my-company-opencost-athena-results-001 | Where Athena writes query results |
| `athenaDatabase` | opencost_db | Glue database containing CUR table |
| `athenaTable` | opencost | Table name (created by Glue Crawler) |
| `athenaRegion` | us-east-1 | AWS region (must be us-east-1 for CUR) |

---

## Post-Deployment Verification Steps

### Step 1: Wait 24 Hours for First CUR Delivery

```bash
# Check if CUR files exist
aws s3 ls s3://my-company-billing-data-storage-001/cur/opencost/opencost/ --recursive

# Expected output (after 24 hours):
2024-02-05 10:00:00  15728640  cur/opencost/opencost/year=2024/month=02/day=05/data-00001.snappy.parquet
2024-02-05 11:00:00  15634432  cur/opencost/opencost/year=2024/month=02/day=05/data-00002.snappy.parquet

# ❌ If you see nothing → Wait, AWS takes 24 hours
# ✅ If you see Parquet files → Proceed to Step 2
```

### Step 2: Run Glue Crawler

```bash
# Start crawler manually (first time)
aws glue start-crawler --name opencost_crawler

# Check crawler status
aws glue get-crawler --name opencost_crawler | jq '.Crawler.State'
# Expected: "RUNNING" → wait 2-5 minutes
# Expected: "READY" → crawler finished

# Verify table created
aws glue get-table --database-name opencost_db --name opencost

# Expected output:
{
  "Table": {
    "Name": "opencost",
    "DatabaseName": "opencost_db",
    "StorageDescriptor": {
      "Columns": [
        {"Name": "identity_line_item_id", "Type": "string"},
        {"Name": "line_item_unblended_cost", "Type": "double"},
        {"Name": "resource_tags_user_name", "Type": "string"},
        ... (100+ more columns)
      ],
      "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
      ...
    }
  }
}
```

### Step 3: Test Athena Query

```bash
# Run test query
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM opencost_db.opencost" \
  --result-configuration "OutputLocation=s3://my-company-opencost-athena-results-001/" \
  --query-execution-context "Database=opencost_db"

# Save query ID from output
QUERY_ID="abc123-def456-ghi789"

# Check query status
aws athena get-query-execution --query-execution-id $QUERY_ID | jq '.QueryExecution.Status.State'
# Expected: "SUCCEEDED"

# Get results
aws athena get-query-results --query-execution-id $QUERY_ID

# Expected output:
{
  "ResultSet": {
    "Rows": [
      {"Data": [{"VarCharValue": "_col0"}]},
      {"Data": [{"VarCharValue": "15234"}]}  # Number of billing records
    ]
  }
}

# ✅ If query succeeds → OpenCost will work
# ❌ If query fails → Check IAM permissions and S3 paths
```

### Step 4: Verify OpenCost Pod Can Query

```bash
# Check OpenCost logs
kubectl logs -n opencost -l app=opencost --tail=100

# Expected log entries:
[INFO] Connecting to Athena: database=opencost_db, table=opencost
[INFO] Pod Identity credentials loaded: role=arn:aws:iam::123456789012:role/OpenCostPodRole
[INFO] Running query: SELECT line_item_unblended_cost FROM opencost_db.opencost WHERE ...
[INFO] Query succeeded: execution_id=abc123-def456
[INFO] Retrieved 1,234 cost records from Athena
[INFO] Cost allocation complete: 45 pods with cost data

# ❌ If you see errors:
[ERROR] Access Denied (S3 GetObject)
  → Check IAM policy includes s3:GetObject on opencost_cur bucket

[ERROR] Access Denied (Athena StartQueryExecution)
  → Check IAM policy includes athena:* permissions

[ERROR] Table not found: opencost_db.opencost
  → Run Glue Crawler again

[ERROR] No data returned from Athena
  → Wait for CUR delivery (24 hours)
```

### Step 5: Verify Cost Data in Dashboard

```bash
# Port-forward to OpenCost UI
kubectl port-forward -n opencost svc/opencost 9090:9090

# Open browser: http://localhost:9090

# Check dashboard shows:
# - Total cluster cost (should match AWS bill)
# - Cost per namespace
# - Cost per pod
# - Cost breakdown (compute, storage, network)
```

---

## Configuration Verification Checklist

Let's verify your configuration will work correctly:

### ✅ **Infrastructure Layer**

- [ ] **S3 Bucket Policy**: Includes `aws:SourceAccount` condition (security)
- [ ] **CUR Settings**:
  - [ ] `time_unit = "HOURLY"` (accurate Spot pricing)
  - [ ] `format = "Parquet"` (10x faster queries)
  - [ ] `additional_schema_elements = ["RESOURCES"]` (pod-level costs)
  - [ ] `s3_region = "us-east-1"` (CUR requirement)
- [ ] **Glue Crawler Path**: Matches `s3://bucket/cur/opencost/opencost/`
- [ ] **Both S3 Buckets Created**: opencost_cur + opencost_results

### ✅ **IAM Permissions Layer**

**Glue Crawler Role:**
- [ ] Trust policy allows `glue.amazonaws.com`
- [ ] Has `AWSGlueServiceRole` managed policy
- [ ] Has custom policy for `s3:GetObject` on CUR bucket

**OpenCost Pod Role:**
- [ ] Trust policy allows `pods.eks.amazonaws.com`
- [ ] Has `athena:*` permissions
- [ ] Has `glue:GetTable`, `glue:GetPartitions`, `glue:GetDatabase`
- [ ] Has `s3:GetObject` on BOTH buckets
- [ ] Has `s3:PutObject` on results bucket

### ✅ **Kubernetes Layer**

- [ ] **ServiceAccount Created**:
  ```bash
  kubectl get sa opencost-sa -n opencost
  ```

- [ ] **Pod Identity Association Created**:
  ```bash
  aws eks list-pod-identity-associations --cluster-name <cluster>
  ```

- [ ] **Secret Mounted in Pod**:
  ```yaml
  volumes:
    - name: cloud-integration
      secret:
        secretName: cloud-integration
  volumeMounts:
    - name: cloud-integration
      mountPath: /var/opencost/config
  ```

- [ ] **Prometheus URL Correct**:
  ```yaml
  prometheus:
    external:
      url: "http://prom-monitor-prometheus.monitoring.svc:80"
  ```

### ✅ **Timeline Expectations**

```
Day 0 (Today):
├─ Run terraform apply
├─ All resources created
├─ CUR definition active
└─ Status: Waiting for AWS

Day 1 (24 hours later):
├─ First CUR files delivered to S3
├─ Run Glue Crawler manually
├─ Athena table created
├─ Test Athena query succeeds
├─ Deploy OpenCost Helm chart
└─ Status: OpenCost working with yesterday's data

Day 2+:
├─ CUR updates hourly
├─ OpenCost shows real-time costs
├─ Dashboard shows cost trends
└─ Status: Fully operational
```

---

## Common Mistakes to Avoid

### ❌ Mistake 1: Wrong Glue Crawler Path

```hcl
# ❌ WRONG - Missing double "opencost"
s3_target {
  path = "s3://${aws_s3_bucket.opencost_cur.bucket}/cur/"
}

# ✅ CORRECT - Matches CUR output structure
s3_target {
  path = "s3://${aws_s3_bucket.opencost_cur.bucket}/cur/opencost/opencost/"
}
```

**Why:** AWS CUR creates: `s3://bucket/{prefix}/{report_name}/{report_name}/`

### ❌ Mistake 2: Missing RESOURCES Schema Element

```hcl
# ❌ WRONG - No resource IDs
additional_schema_elements = []

# ✅ CORRECT - Includes resource IDs for pod attribution
additional_schema_elements = ["RESOURCES"]
```

**Impact:** OpenCost shows total costs but cannot attribute to specific pods

### ❌ Mistake 3: Daily Instead of Hourly

```hcl
# ❌ WRONG - Inaccurate for Spot instances
time_unit = "DAILY"

# ✅ CORRECT - Accurate partial-hour charges
time_unit = "HOURLY"
```

**Impact:** Spot instance costs inflated (shows full-day charge for 10-minute pod)

### ❌ Mistake 4: CSV Instead of Parquet

```hcl
# ❌ WRONG - 10x slower + 10x more expensive Athena queries
format = "text/csv"

# ✅ CORRECT - Optimized for Athena
format = "Parquet"
```

**Impact:** $50/month Athena costs vs $5/month with Parquet

### ❌ Mistake 5: Missing S3 Bucket Policy

```hcl
# ❌ WRONG - Bucket created but no policy
resource "aws_s3_bucket" "opencost_cur" {
  bucket = "my-bucket"
}
# Missing: aws_s3_bucket_policy

# ✅ CORRECT - Policy allows AWS Billing Service to write
resource "aws_s3_bucket_policy" "opencost_cur_policy" {
  bucket = aws_s3_bucket.opencost_cur.id
  policy = jsonencode({ ... })
}
```

**Impact:** CUR delivery fails silently - no billing data exported

### ❌ Mistake 6: Wrong Prometheus URL

```yaml
# ❌ WRONG - Missing namespace
url: "http://prom-monitor-prometheus:80"

# ✅ CORRECT - Full DNS path
url: "http://prom-monitor-prometheus.monitoring.svc:80"
```

**Impact:** OpenCost cannot connect to Prometheus - no metrics

---

## Cost Estimates

### AWS Infrastructure Costs

| Resource | Monthly Cost | Notes |
|----------|--------------|-------|
| S3 (CUR Data) | $3-5 | ~150GB for medium cluster |
| S3 (Athena Results) | $0.50 | Small temporary files |
| Athena Queries | $2-5 | ~1TB scanned/month @ $5/TB |
| Glue Crawler | $0.44 | $0.44/DPU-hour, weekly runs |
| **TOTAL** | **$6-11/month** | |

### ROI Calculation

```
Cost: $10/month for OpenCost infrastructure

Savings examples:
1. Find over-provisioned pods: 20% resource reduction
   $1,000/month cluster → Save $200/month
   ROI: 20x

2. Shut down idle dev environments after hours
   $500/month idle → Save $300/month
   ROI: 30x

3. Move batch jobs to Spot instances
   $800/month on-demand → $320 on Spot (60% savings)
   Savings: $480/month
   ROI: 48x

Average ROI: 10-100x the cost of OpenCost
```

---

## Configuration with External Secrets Operator

For maximum security, store cloud integration config in AWS Secrets Manager:

```yaml
---
# Create AWS Secrets Manager secret
# Name: opencost/cloud-integration
# Value:
{
  "AWS_ACCESS_KEY_ID": "AKIAIOSFODNN7EXAMPLE",
  "AWS_SECRET_ACCESS_KEY": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "SPOT_DATA_FEED_BUCKET": "s3://my-spot-data-bucket"
}

---
# Use External Secrets Operator to sync
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: opencost-cloud-integration
  namespace: robot-shop
spec:
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  
  refreshInterval: 1h
  
  target:
    name: cloud-integration  # Kubernetes secret name
    creationPolicy: Owner
  
  data:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: opencost/cloud-integration
        property: AWS_ACCESS_KEY_ID
    
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: opencost/cloud-integration
        property: AWS_SECRET_ACCESS_KEY
    
    - secretKey: SPOT_DATA_FEED_BUCKET
      remoteRef:
        key: opencost/cloud-integration
        property: SPOT_DATA_FEED_BUCKET
```

**Alternative: ConfigMap for non-sensitive data**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: opencost-config
  namespace: robot-shop
data:
  PROMETHEUS_URL: "http://prom-monitor-prometheus.monitoring.svc:80"
  CLUSTER_NAME: "my-eks-cluster"
  SPOT_DATA_ENABLED: "true"
  SPOT_DATA_FEED_BUCKET: "s3://my-spot-data-bucket"
```

---

## Complete OpenCost Configuration Example

```yaml
opencost:
  enabled: true
  clusterName: "my-eks-cluster"

  opencost:
    # Cloud cost integration (AWS)
    cloudCost:
      enabled: true
    
    # Secret for AWS credentials
    cloudIntegrationSecret: "cloud-integration"
    
    # Connection to Prometheus
    prometheus:
      internal:
        enabled: false
      external:
        enabled: true
        # CRITICAL: Correct URL format
        url: "http://prom-monitor-prometheus.monitoring.svc:80"
    
    # ServiceAccount
    serviceAccount:
      create: true
      name: "opencost-sa"
    
    # UI (Dashboard)
    ui:
      ingress:
        enabled: "true"
        ingressClassName: traefik
        annotations:
          traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt

        hosts:
        - host: opencost.yourdomain.com

        tls: 
           - secretName: opencost-tls
             hosts:
               - opencost.yourdomain.com

    # Resources
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

---

## Troubleshooting

### Problem: "Cannot connect to Prometheus"

**Check URL format:**
```bash
# Inside OpenCost pod, test Prometheus connection
kubectl exec -it <opencost-pod> -- curl http://prom-monitor-prometheus.monitoring.svc:80/-/healthy

# Should return 200 OK
```

**Common URL mistakes:**
```yaml
# ❌ Wrong: Missing namespace
url: "http://prom-monitor-prometheus:80"
# Works only if in same namespace

# ❌ Wrong: Wrong port
url: "http://prom-monitor-prometheus.monitoring.svc:9090"
# Should be 80 (exposed port, not 9090 internal)

# ✅ Correct
url: "http://prom-monitor-prometheus.monitoring.svc:80"
```

### Problem: "Spot pricing data not available"

```
Timeline issue: S3 bucket configured but no data yet

Day 1:
- Create S3 bucket
- Configure AWS spot data feed
- OpenCost sees bucket but no files
- Status: "Waiting for data"

Day 2:
- AWS delivers first batch of spot prices
- OpenCost reads from S3
- Now has accurate pricing

Action: Wait 24 hours or use AWS Pricing API as fallback
```

### Problem: High memory usage

```yaml
# OpenCost can use lots of RAM when calculating large clusters
# Solutions:
1. Increase resource limits:
   limits:
     memory: 2Gi

2. Or enable caching:
   CACHE_ENABLED: "true"
   CACHE_TTL: "3600"

3. Or reduce query scope (filter namespaces)
```

---

## Dashboard Usage

OpenCost provides several views:

### 1. **Cost Overview**
```
Shows:
- Total cluster cost
- Cost per node
- Cost per namespace
- Cost breakdown by resource (compute, storage, network)
```

### 2. **Namespace Breakdown**
```
Shows per-namespace:
- Total monthly cost
- CPU cost allocation
- Memory cost allocation
- Storage cost allocation
- Trend over time
```

### 3. **Pod Breakdown**
```
Shows per-pod:
- CPU consumed vs allocated
- Memory consumed vs allocated
- Current cost
- Projected monthly cost
```

### 4. **Efficiency Analysis**
```
Shows:
- Over-provisioned pods (allocated but not used)
- Under-provisioned pods (usage approaching limit)
- Idle resources
- Optimization recommendations
```

---

## Cost Optimization with OpenCost

### Finding Cost Savings

```bash
# 1. Find over-provisioned pods
# Dashboard → Pod view → Filter by "utilization < 20%"
# Example: Pod requesting 4 GB RAM but using 200 MB
# Action: Reduce limit to 512 MB, save 87.5%

# 2. Find idle namespaces
# Dashboard → Namespace view → Filter by "cost > $100"
# Example: Staging namespace running expensive GPU nodes
# Action: Shut down staging after hours

# 3. Find long-running batch jobs
# Dashboard → Pod view → Sort by "monthly cost"
# Example: Data processing job = $500/month
# Action: Optimize or run during off-peak hours
```

---

## Production Checklist

- [ ] Prometheus connection verified and working
- [ ] AWS IAM policy attached to OpenCost
- [ ] Pod Identity association created
- [ ] S3 bucket for spot data created
- [ ] AWS spot data feed subscription configured
- [ ] Wait 24 hours for first spot data delivery
- [ ] Cloud integration secret created
- [ ] Ingress configured with TLS
- [ ] Monitor OpenCost logs for errors
- [ ] Verify costs match AWS bills (first reconciliation)
- [ ] Set up alerting for cost anomalies
- [ ] Train team on dashboard usage
- [ ] Create cost optimization runbooks

---

## Reference

- [OpenCost Documentation](https://www.opencost.io/)
- [OpenCost Helm Chart](https://github.com/opencost/opencost-helm-chart)
- [OpenCost AWS Integration](https://www.opencost.io/docs/configuration/cloudcost/aws)
- [AWS EC2 Pricing API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/price-changes.html)
- [OpenCost Kubectl Plugin](https://www.opencost.io/docs/integrations/kubectl)
