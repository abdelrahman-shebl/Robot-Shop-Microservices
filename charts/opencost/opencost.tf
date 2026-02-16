# ═══════════════════════════════════════════════════════════════════════════════
# OPENCOST AWS INFRASTRUCTURE - COMPLETE SETUP (NO MODULES)
# ═══════════════════════════════════════════════════════════════════════════════
# 
# This Terraform configuration creates ALL required AWS resources for OpenCost
# to track and report your Kubernetes costs using AWS Cost & Usage Reports (CUR).
#
# ARCHITECTURE OVERVIEW:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                                                                             │
# │  AWS Billing → S3 (CUR Data) → Glue Crawler → Athena Table                │
# │                                      ↓                                      │
# │                          OpenCost Pod ← Pod Identity Role                  │
# │                                      ↓                                      │
# │                          S3 (Query Results) ← Athena                       │
# │                                                                             │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# WHY THIS APPROACH IS BETTER THAN MODULES:
# ─────────────────────────────────────────
# 1. **Transparency**: Every resource is explicitly defined - no hidden defaults
# 2. **Parquet Format**: Explicitly set to make Athena queries 10x faster/cheaper
# 3. **Resource IDs**: Enabled via additional_schema_elements = ["RESOURCES"]
#    Without this, OpenCost cannot attribute costs to specific pods
# 4. **No Lambda Issues**: Uses Glue Crawler (serverless) instead of Lambda
#    functions that might hit "Deprecated Runtime" errors
# 5. **Full Control**: Easy to customize regions, naming, retention policies
#
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: AWS BILLING DATA INFRASTRUCTURE
# ═══════════════════════════════════════════════════════════════════════════════
# This section creates the storage and reporting infrastructure for AWS billing data

# ───────────────────────────────────────────────────────────────────────────────
# 1.1 S3 BUCKET FOR COST & USAGE REPORTS (CUR)
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Primary storage for AWS billing data exported by the CUR service
# WHY: AWS needs a place to dump hourly billing records (EC2, EBS, data transfer)
# HOW IT WORKS:
#   - AWS Billing Service writes Parquet files here every hour
#   - Files are organized by date: s3://bucket/cur/opencost/opencost/year=2024/month=02/
#   - Each file contains resource-level cost data (pod IDs, instance IDs, etc.)
# COST: Free storage for first 30 days, then ~$0.023/GB/month (usually <$5/month)
resource "aws_s3_bucket" "opencost_cur" {
  bucket        = "my-company-billing-data-storage-001"  # CHANGE THIS to match your naming
  force_destroy = true  # Allows Terraform to delete bucket with data (dev/test only)
}

# ───────────────────────────────────────────────────────────────────────────────
# 1.2 S3 BUCKET POLICY - ALLOW AWS BILLING SERVICE TO WRITE
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Grants AWS Billing Service permission to write CUR files to your bucket
# WHY: Without this policy, AWS cannot deliver billing reports to your bucket
# HOW IT WORKS:
#   - AWS Billing Service (billingreports.amazonaws.com) needs permission to:
#     1. s3:GetBucketAcl - Verify it has permission to write
#     2. s3:PutObject - Write the actual Parquet billing files
#   - Condition restricts this to ONLY your AWS account (security best practice)
#
# SECURITY NOTE:
# ──────────────
# The Condition block ensures that only billing reports from YOUR account can
# write to this bucket. Without this, a malicious actor could potentially write
# fake billing data if they knew your bucket name.
resource "aws_s3_bucket_policy" "opencost_cur_policy" {
  bucket = aws_s3_bucket.opencost_cur.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCURWrite"
        Effect = "Allow"
        # This is the critical part: granting access to the AWS Billing Service
        Principal = { Service = "billingreports.amazonaws.com" }
        Action = [
          "s3:GetBucketAcl",  # Billing service checks permissions first
          "s3:PutObject"      # Then writes billing files
        ]
        Resource = [
          aws_s3_bucket.opencost_cur.arn,        # Bucket itself (for GetBucketAcl)
          "${aws_s3_bucket.opencost_cur.arn}/*"  # All objects in bucket (for PutObject)
        ]
        # Security Best Practice: Only allow billing reports from YOUR account
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ───────────────────────────────────────────────────────────────────────────────
# 1.3 COST & USAGE REPORT (CUR) DEFINITION
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Tells AWS Billing Service WHAT to export, HOW, and WHERE
# WHY: Without this, AWS doesn't generate any billing exports
# HOW IT WORKS:
#   - AWS creates hourly snapshots of your account's resource usage
#   - Includes tags, instance metadata, and resource IDs (critical for OpenCost)
#   - Data flows: AWS Billing → Parquet files → S3 → Glue → Athena → OpenCost
resource "aws_cur_report_definition" "opencost" {
  report_name = "opencost"  # Name appears in S3 path structure
  
  # TIME GRANULARITY: HOURLY vs DAILY
  # ─────────────────────────────────
  # HOURLY is REQUIRED for accurate Spot Instance cost tracking because:
  # - Spot instances can terminate mid-hour, causing partial-hour charges
  # - DAILY aggregation would show full-day cost even if pod ran 10 minutes
  # - OpenCost needs hourly breakdowns to calculate per-pod costs correctly
  time_unit = "HOURLY"
  
  # FILE FORMAT: PARQUET vs CSV
  # ────────────────────────────
  # Parquet is a columnar format that makes Athena queries:
  # - 10x FASTER: Only reads columns you query (not entire rows)
  # - 10x CHEAPER: Less data scanned = lower Athena costs
  # - SMALLER: ~70% smaller files than CSV (lower S3 costs)
  format      = "Parquet"
  compression = "Parquet"  # Built-in compression for Parquet format
  
  # RESOURCE IDs: THE CRITICAL SETTING
  # ───────────────────────────────────
  # This adds resource identifiers (EC2 instance IDs, EBS volume IDs) to reports
  # WITHOUT THIS: OpenCost shows "$150 spent on EC2" (useless)
  # WITH THIS: OpenCost shows "$75 on web-pod-abc, $50 on db-pod-xyz, $25 on redis-pod-123"
  # 
  # How it works:
  # - AWS tags EC2 instances with Kubernetes pod names
  # - CUR exports these tags when RESOURCES is enabled
  # - OpenCost matches pod names to costs using these tags
  additional_schema_elements = ["RESOURCES"]
  
  # S3 LOCATION SETTINGS
  # ────────────────────
  s3_bucket = aws_s3_bucket.opencost_cur.id
  s3_region = "us-east-1"  # CUR must be in us-east-1 (AWS requirement)
  s3_prefix = "cur"        # Creates path: s3://bucket/cur/opencost/opencost/...
  
  # VERSIONING: OVERWRITE vs CREATE_NEW_REPORT
  # ───────────────────────────────────────────
  # OVERWRITE_REPORT: Replaces previous data in same location (saves space)
  # CREATE_NEW_REPORT: Keeps historical snapshots (useful for auditing)
  report_versioning = "OVERWRITE_REPORT"
}

# ───────────────────────────────────────────────────────────────────────────────
# 1.4 S3 BUCKET FOR ATHENA QUERY RESULTS
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Temporary storage for Athena query outputs
# WHY: Athena REQUIRES a results bucket - it cannot return results directly
# HOW IT WORKS:
#   1. OpenCost sends query: "SELECT cost FROM opencost WHERE pod='nginx-pod'"
#   2. Athena executes query on CUR data in bucket #1
#   3. Athena writes results to THIS bucket as CSV files
#   4. OpenCost reads CSV results from this bucket
#   5. Results auto-expire (can add lifecycle policy to delete after 7 days)
# COST: Minimal (~$0.50/month), results are small (<1MB each)
resource "aws_s3_bucket" "opencost_results" {
  bucket        = "my-company-opencost-athena-results-001"  # CHANGE THIS
  force_destroy = true  # Safe to delete - results are temporary
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: AWS GLUE - AUTOMATIC SCHEMA DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════
# Glue Crawler automatically discovers the schema of CUR files and creates Athena tables

# ───────────────────────────────────────────────────────────────────────────────
# 2.1 GLUE DATABASE
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: A logical container for Athena tables (like a schema in PostgreSQL)
# WHY: Athena needs a database to organize tables
# HOW IT WORKS:
#   - Acts as namespace: opencost_db.opencost_table
#   - Multiple crawlers can populate the same database
#   - Appears in Athena UI under "Databases" dropdown
resource "aws_glue_catalog_database" "opencost" {
  name = "opencost_db"
}

# ───────────────────────────────────────────────────────────────────────────────
# 2.2 GLUE CRAWLER
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Serverless service that scans S3 files and auto-creates Athena table schema
# WHY: CUR files have complex nested Parquet schema - manual creation is error-prone
# HOW IT WORKS:
#   1. Crawler runs on schedule (or manually triggered)
#   2. Reads sample Parquet files from S3 path
#   3. Infers schema: column names, data types, partitions
#   4. Creates/updates Athena table in Glue Catalog
#   5. OpenCost can now query: SELECT * FROM opencost_db.opencost
#
# SCHEDULE: Run crawler after first CUR delivery (24 hours), then weekly
# You trigger it manually:
#   aws glue start-crawler --name opencost_crawler
resource "aws_glue_crawler" "opencost" {
  name          = "opencost_crawler"
  database_name = aws_glue_catalog_database.opencost.name
  role          = aws_iam_role.glue_crawler.arn
  
  # S3 PATH TO SCAN
  # ───────────────
  # IMPORTANT: This path MUST match the CUR output structure
  # AWS creates: s3://bucket/cur/opencost/opencost/year=2024/month=02/...
  # The double "opencost" is intentional:
  #   - First: s3_prefix from CUR definition
  #   - Second: report_name from CUR definition
  s3_target {
    path = "s3://${aws_s3_bucket.opencost_cur.bucket}/cur/opencost/opencost/"
  }
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: IAM PERMISSIONS FOR GLUE CRAWLER
# ═══════════════════════════════════════════════════════════════════════════════
# Glue Crawler needs permissions to read S3 and write to Glue Catalog

# ───────────────────────────────────────────────────────────────────────────────
# 3.1 GLUE CRAWLER IAM ROLE
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: IAM role that the Glue Crawler service assumes
# WHY: AWS services need explicit permission to act on your behalf
# HOW IT WORKS:
#   - Trust policy allows glue.amazonaws.com to assume this role
#   - Service role provides default Glue permissions (read Glue Catalog)
#   - Custom policy (below) adds S3 read permissions
resource "aws_iam_role" "glue_crawler" {
  name = "opencost-glue-crawler-role"
  
  # TRUST POLICY: Who can assume this role?
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

# ───────────────────────────────────────────────────────────────────────────────
# 3.2 ATTACH AWS MANAGED POLICY FOR GLUE
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: AWS-managed policy that grants basic Glue Crawler permissions
# INCLUDES:
#   - glue:GetDatabase, glue:CreateTable, glue:UpdateTable
#   - glue:GetPartitions, glue:CreatePartition
#   - logs:CreateLogGroup, logs:PutLogEvents (for CloudWatch logging)
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# ───────────────────────────────────────────────────────────────────────────────
# 3.3 CUSTOM POLICY: S3 ACCESS FOR CRAWLER
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Grants Glue Crawler permission to read CUR data from S3
# WHY: AWSGlueServiceRole doesn't include S3 access (security best practice)
# PERMISSIONS:
#   - s3:GetObject: Read Parquet files to infer schema
#   - s3:PutObject: Not strictly needed for crawler, but useful for debugging
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


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: IAM PERMISSIONS FOR OPENCOST POD
# ═══════════════════════════════════════════════════════════════════════════════
# OpenCost pod needs permissions to query Athena and access both S3 buckets

# ───────────────────────────────────────────────────────────────────────────────
# 4.1 IAM ROLE FOR OPENCOST POD (EKS POD IDENTITY)
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: IAM role assumed by the OpenCost pod running in EKS
# WHY: Pod Identity allows Kubernetes pods to use IAM roles without keys
# HOW IT WORKS:
#   - EKS injects temporary credentials into pod via aws-sdk
#   - Credentials auto-rotate every 15 minutes (secure)
#   - Pod uses these credentials to call Athena/S3 APIs
#
# POD IDENTITY vs IRSA (IAM Roles for Service Accounts):
# ───────────────────────────────────────────────────────
# | Feature           | Pod Identity      | IRSA            |
# |-------------------|-------------------|-----------------|
# | Setup Complexity  | Simpler           | More complex    |
# | OIDC Provider     | Not required      | Required        |
# | Token Expiration  | 15 min            | 1 hour          |
# | EKS Versions      | 1.24+             | 1.13+           |
# | AWS Service       | pods.eks.aws.com  | oidc.eks.aws    |
resource "aws_iam_role" "opencost_pod" {
  name = "OpenCostPodRole"
  
  # TRUST POLICY FOR POD IDENTITY
  # ──────────────────────────────
  # This allows the EKS Pod Identity Agent to assume this role
  # The agent runs as a DaemonSet on every node and manages credentials
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"  # Pod Identity service
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"  # Allows adding session tags (useful for CloudTrail)
      ]
    }]
  })
}

# ───────────────────────────────────────────────────────────────────────────────
# 4.2 INLINE POLICY: ATHENA AND S3 PERMISSIONS
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Grants OpenCost pod permission to query Athena and access S3 buckets
# WHY: OpenCost needs to run Athena queries and read results from S3
#
# PERMISSION BREAKDOWN:
# ─────────────────────
resource "aws_iam_role_policy" "opencost_access" {
  name = "opencost-access"
  role = aws_iam_role.opencost_pod.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # STATEMENT 1: ATHENA QUERY PERMISSIONS
      # ──────────────────────────────────────
      # Allows OpenCost to:
      # - athena:StartQueryExecution: Run SQL queries
      # - athena:GetQueryExecution: Check query status
      # - athena:GetQueryResults: Fetch query results
      # - athena:StopQueryExecution: Cancel long-running queries
      # - glue:GetTable: Read table schema from Glue Catalog
      # - glue:GetPartitions: Read partition metadata (year=2024/month=02)
      # - glue:GetDatabase: Read database metadata
      {
        Effect = "Allow"
        Action = [
          "athena:*",                  # All Athena operations (can scope down to specific actions)
          "glue:GetTable",             # Read table schema
          "glue:GetPartitions",        # Read partition info (for partition pruning)
          "glue:GetDatabase"           # Read database info
        ]
        Resource = "*"  # Can scope to specific database ARN for tighter security
      },
      
      # STATEMENT 2: S3 BUCKET PERMISSIONS
      # ───────────────────────────────────
      # Allows OpenCost to:
      # 
      # READ CUR DATA (opencost_cur bucket):
      # - s3:GetBucketLocation: Find bucket region (required by SDK)
      # - s3:GetObject: Read Parquet files during Athena queries
      # - s3:ListBucket: List files in bucket (for partition discovery)
      #
      # WRITE QUERY RESULTS (opencost_results bucket):
      # - s3:PutObject: Athena writes query results here
      # - s3:ListBucket: Check if results already exist
      # - s3:ListBucketMultipartUploads: Manage large result uploads
      # - s3:ListMultipartUploadParts: Track upload progress
      # - s3:AbortMultipartUpload: Cancel failed uploads
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",           # Required by AWS SDK to find bucket
          "s3:GetObject",                   # Read CUR data + query results
          "s3:ListBucket",                  # List files in buckets
          "s3:ListBucketMultipartUploads",  # For large query results
          "s3:ListMultipartUploadParts",    # Track multipart uploads
          "s3:AbortMultipartUpload",        # Cancel failed uploads
          "s3:PutObject"                    # Write query results
        ]
        Resource = [
          # CUR Data Bucket (READ)
          aws_s3_bucket.opencost_cur.arn,
          "${aws_s3_bucket.opencost_cur.arn}/*",
          
          # Athena Results Bucket (READ + WRITE)
          aws_s3_bucket.opencost_results.arn,
          "${aws_s3_bucket.opencost_results.arn}/*"
        ]
      }
    ]
  })
}

# ───────────────────────────────────────────────────────────────────────────────
# 4.3 POD IDENTITY ASSOCIATION
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Links the IAM role to a specific Kubernetes ServiceAccount
# WHY: Tells EKS "When 'opencost-sa' pod starts in 'opencost' namespace, inject this role"
# HOW IT WORKS:
#   1. OpenCost pod starts with serviceAccountName: opencost-sa
#   2. EKS Pod Identity Agent detects the pod
#   3. Agent calls sts:AssumeRole to get temporary credentials
#   4. Agent injects credentials into pod as environment variables:
#      - AWS_ROLE_ARN
#      - AWS_WEB_IDENTITY_TOKEN_FILE
#   5. AWS SDK in OpenCost pod uses these credentials automatically
#
# REQUIREMENTS:
# ─────────────
# - EKS cluster must have Pod Identity Addon enabled
# - ServiceAccount must exist: kubectl create sa opencost-sa -n opencost
# - No annotations needed on ServiceAccount (unlike IRSA)
resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    = aws_eks_cluster.main.name  # CHANGE THIS to your cluster name
  namespace       = "opencost"
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_pod.arn
}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: HELPER DATA SOURCES
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# 5.1 AWS ACCOUNT ID
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Fetches current AWS account ID dynamically
# WHY: Needed for OpenCost's cloud-integration.json configuration
# USAGE: Referenced in output as data.aws_caller_identity.current.account_id
data "aws_caller_identity" "current" {}


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: TERRAFORM OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════════
# These outputs provide the exact values needed for OpenCost configuration

# ───────────────────────────────────────────────────────────────────────────────
# 6.1 OPENCOST CONFIGURATION VALUES
# ───────────────────────────────────────────────────────────────────────────────
# WHAT: Structured output containing all values for cloud-integration.json
# WHY: Makes it easy to copy-paste into OpenCost configuration
# 
# HOW TO USE:
# ───────────
# 1. Run: terraform output -json OPENCOST_CONFIG > config.json
# 2. Create Kubernetes secret:
#    kubectl create secret generic cloud-integration \
#      --from-file=cloud-integration.json=config.json \
#      -n opencost
# 3. Mount secret in OpenCost pod (see Helm values)
#
# CONFIGURATION EXPLAINED:
# ────────────────────────
output "OPENCOST_CONFIG" {
  description = "Copy these values to cloud-integration.json for OpenCost Helm chart"
  
  value = {
    # AWS ACCOUNT ID
    # ──────────────
    # Your 12-digit AWS account number
    # Used by OpenCost to identify which account's costs to query
    projectID = data.aws_caller_identity.current.account_id
    
    # ATHENA RESULTS BUCKET
    # ─────────────────────
    # Where Athena writes query results
    # OpenCost reads results from here after queries complete
    athenaBucketName = aws_s3_bucket.opencost_results.bucket
    
    # GLUE DATABASE NAME
    # ──────────────────
    # The database containing the CUR table
    # OpenCost queries: SELECT * FROM <athenaDatabase>.<athenaTable>
    athenaDatabase = aws_glue_catalog_database.opencost.name
    
    # ATHENA TABLE NAME
    # ─────────────────
    # The table name created by Glue Crawler
    # Usually matches the CUR report name ("opencost")
    # Verify after first crawler run:
    #   aws glue get-tables --database-name opencost_db
    athenaTable = "opencost"
    
    # AWS REGION
    # ──────────
    # Region where CUR and Athena resources exist
    # Must be "us-east-1" for CUR (AWS requirement)
    athenaRegion = "us-east-1"
  }
  
  # Example output format:
  # {
  #   "projectID": "123456789012",
  #   "athenaBucketName": "my-company-opencost-athena-results-001",
  #   "athenaDatabase": "opencost_db",
  #   "athenaTable": "opencost",
  #   "athenaRegion": "us-east-1"
  # }
}


# ═══════════════════════════════════════════════════════════════════════════════
# POST-DEPLOYMENT CHECKLIST
# ═══════════════════════════════════════════════════════════════════════════════
# 
# After running `terraform apply`, complete these steps:
#
# 1. WAIT 24 HOURS for first CUR delivery
#    - AWS takes 24 hours to generate first CUR files
#    - Check S3: s3://my-company-billing-data-storage-001/cur/opencost/opencost/
#    - You should see Parquet files appear
#
# 2. RUN GLUE CRAWLER manually (first time only)
#    aws glue start-crawler --name opencost_crawler
#    - Waits for crawler to finish (usually 2-5 minutes)
#    - Verify table created: aws glue get-table --database-name opencost_db --name opencost
#
# 3. TEST ATHENA QUERY manually
#    aws athena start-query-execution \
#      --query-string "SELECT * FROM opencost_db.opencost LIMIT 10" \
#      --result-configuration "OutputLocation=s3://my-company-opencost-athena-results-001/" \
#      --query-execution-context "Database=opencost_db"
#    - If this works, OpenCost will work
#
# 4. CREATE KUBERNETES SECRET with config
#    terraform output -json OPENCOST_CONFIG | jq > /tmp/cloud-integration.json
#    kubectl create namespace opencost
#    kubectl create secret generic cloud-integration \
#      --from-file=cloud-integration.json=/tmp/cloud-integration.json \
#      -n opencost
#
# 5. INSTALL OPENCOST HELM CHART
#    helm install opencost opencost/opencost \
#      --namespace opencost \
#      --values values-opencost.yaml
#    (Ensure values.yaml mounts the cloud-integration secret)
#
# 6. VERIFY OPENCOST IS WORKING
#    kubectl logs -n opencost -l app=opencost | grep -i athena
#    - Should see: "Successfully queried Athena"
#    - Check UI: kubectl port-forward -n opencost svc/opencost 9090:9090
#      Open: http://localhost:9090
#
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
# COST BREAKDOWN (MONTHLY ESTIMATES)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Resource                       | Cost/Month | Notes
# -------------------------------|------------|----------------------------------------
# S3 Storage (CUR Data)          | $3-5       | ~150GB/month for medium cluster
# S3 Storage (Athena Results)    | $0.50      | Small temporary files
# Athena Queries                 | $2-5       | ~1TB scanned/month, $5/TB
# Glue Crawler Runs              | $0.44      | $0.44/DPU-hour, weekly runs
# -------------------------------|------------|----------------------------------------
# TOTAL                          | $6-11/mo   | Saves $500-5000/mo in cost visibility
#
# ROI: If OpenCost helps you right-size pods by 20%, you save 10-100x this cost
# ═══════════════════════════════════════════════════════════════════════════════
