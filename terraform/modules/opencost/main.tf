# 1.1 S3 BUCKET FOR COST & USAGE REPORTS (CUR)
resource "aws_s3_bucket" "opencost_cur" {
  bucket        = "billing-data-storage-0022"  # CHANGE THIS to match your naming
  force_destroy = true  # Allows Terraform to delete bucket with data (dev/test only)
}
# 1.2 S3 BUCKET POLICY - ALLOW AWS BILLING SERVICE TO WRITE
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
# 1.3 COST & USAGE REPORT (CUR) DEFINITION
resource "aws_cur_report_definition" "opencost" {
  report_name = "opencost"  
  
  # TIME GRANULARITY: HOURLY vs DAILY
  time_unit = "HOURLY"
  
  # FILE FORMAT: PARQUET

  format      = "Parquet"
  compression = "Parquet" 
  
  # RESOURCE IDs: THE CRITICAL SETTING
  # This adds resource identifiers (EC2 instance IDs, EBS volume IDs) to reports
  # WITHOUT THIS: OpenCost shows "$150 spent on EC2" (useless)
  # WITH THIS: OpenCost shows "$75 on web-pod-abc, $50 on db-pod-xyz, $25 on redis-pod-123"

  additional_schema_elements = ["RESOURCES"]
  
  # S3 LOCATION SETTINGS
  s3_bucket = aws_s3_bucket.opencost_cur.id
  s3_region = "us-east-1"  # CUR must be in us-east-1 (AWS requirement)
  s3_prefix = "cur"        # Creates path: s3://bucket/cur/opencost/opencost/...
  
  # VERSIONING: OVERWRITE vs CREATE_NEW_REPORT
  report_versioning = "OVERWRITE_REPORT"
}

# 1.4 S3 BUCKET FOR ATHENA QUERY RESULTS

resource "aws_s3_bucket" "opencost_results" {
  bucket        = "my-company-opencost-athena-results-001"  # CHANGE THIS
  force_destroy = true  # Safe to delete - results are temporary
}

# 2.1 GLUE DATABASE

# WHAT: A logical container for Athena tables (like a schema in PostgreSQL)
# WHY: Athena needs a database to organize tables

resource "aws_glue_catalog_database" "opencost" {
  name = "opencost_db"
}

# 2.2 GLUE CRAWLER
# WHAT: Serverless service that scans S3 files and auto-creates Athena table schema
# WHY: CUR files have complex nested Parquet schema - manual creation is error-prone

# SCHEDULE: Run crawler after first CUR delivery (24 hours), then weekly
# You trigger it manually:
#   aws glue start-crawler --name opencost_crawler
resource "aws_glue_crawler" "opencost" {
  name          = "opencost_crawler"
  database_name = aws_glue_catalog_database.opencost.name
  role          = aws_iam_role.glue_crawler.arn
  
  # S3 PATH TO SCAN

  s3_target {
    path = "s3://${aws_s3_bucket.opencost_cur.bucket}/cur/opencost/opencost/"
  }
}

# 3.1 GLUE CRAWLER IAM ROLE
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

# 3.2 ATTACH AWS MANAGED POLICY FOR GLUE
# INCLUDES:
#   - glue:GetDatabase, glue:CreateTable, glue:UpdateTable
#   - glue:GetPartitions, glue:CreatePartition
#   - logs:CreateLogGroup, logs:PutLogEvents (for CloudWatch logging)
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# 3.3 CUSTOM POLICY: S3 ACCESS FOR CRAWLER
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

# SECTION 4: IAM PERMISSIONS FOR OPENCOST POD

resource "aws_iam_role" "opencost_pod" {
  name = "OpenCostPodRole"
  
  # TRUST POLICY FOR POD IDENTITY

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

# 4.2 INLINE POLICY: ATHENA AND S3 PERMISSIONS
# WHAT: Grants OpenCost pod permission to query Athena and access S3 buckets
# WHY: OpenCost needs to run Athena queries and read results from S3

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

# 4.3 POD IDENTITY ASSOCIATION
resource "kubernetes_namespace" "opencost_ns" {
  metadata {
    name = "opencost"
  }
}
resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    =  var.cluster_name #aws_eks_cluster.main.name  
  namespace       = "opencost"
  
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_pod.arn
}

data "aws_caller_identity" "current" {}

resource "kubernetes_secret" "opencost_cloud_integration" {
  metadata {
    name      = "cloud-integration" 
    namespace = "opencost"          
  }

  data = {
    # Terraform builds the JSON string here. No local file needed!
    "cloud-integration.json" = jsonencode({
      aws = {
        projectID        = data.aws_caller_identity.current.account_id
        athenaBucketName = aws_s3_bucket.opencost_results.bucket
        athenaDatabase   = aws_glue_catalog_database.opencost.name
        athenaTable      = "opencost"
        athenaRegion     = "us-east-1"
        usageReport      = "true"
      }
    })
  }
}