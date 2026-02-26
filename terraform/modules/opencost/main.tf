data "aws_caller_identity" "current" {}

# --- 1. S3 BUCKETS (Using Community Module) ---

module "s3_cur" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket        = "opencost-cur-${var.environment}-${var.bucket_suffix}"
  force_destroy = true

  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCURWrite"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:PutObject"]
        Resource = [
          "arn:aws:s3:::opencost-cur-${var.environment}-${var.bucket_suffix}",
          "arn:aws:s3:::opencost-cur-${var.environment}-${var.bucket_suffix}/*"
        ]
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  tags = var.tags
}

module "s3_results" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket        = "opencost-athena-results-${var.environment}-${var.bucket_suffix}"
  force_destroy = true
  tags          = var.tags
}

# --- 2. COST & USAGE REPORT ---

resource "aws_cur_report_definition" "opencost" {
  report_name                = "opencost-${var.environment}"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = module.s3_cur.s3_bucket_id
  s3_region                  = "us-east-1"
  s3_prefix                  = "cur"
  report_versioning          = "OVERWRITE_REPORT"
}

# --- 3. GLUE RESOURCES ---

resource "aws_glue_catalog_database" "opencost" {
  name = "opencost_db_${var.environment}"
}

resource "aws_glue_crawler" "opencost" {
  name          = "opencost_crawler_${var.environment}"
  database_name = aws_glue_catalog_database.opencost.name
  role          = aws_iam_role.glue_crawler.arn
  schedule      = var.crawler_schedule

  s3_target {
    path = "s3://${module.s3_cur.s3_bucket_id}/cur/opencost-${var.environment}/opencost-${var.environment}/"
  }
}

# --- 4. IAM: GLUE CRAWLER ---

resource "aws_iam_role" "glue_crawler" {
  name = "opencost-glue-crawler-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }
    }]
  })
  tags = var.tags
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
      Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"],
      Resource = ["${module.s3_cur.s3_bucket_arn}/*"]
    }]
  })
}

# --- 5. IAM: POD IDENTITY ---

resource "aws_iam_role" "opencost_pod" {
  name = "opencost-pod-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "opencost_access" {
  name = "opencost-access"
  role = aws_iam_role.opencost_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["athena:*", "glue:GetTable", "glue:GetPartitions", "glue:GetDatabase"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket",
          "s3:ListBucketMultipartUploads", "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload", "s3:PutObject"
        ]
        Resource = [
          module.s3_cur.s3_bucket_arn, "${module.s3_cur.s3_bucket_arn}/*",
          module.s3_results.s3_bucket_arn, "${module.s3_results.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# --- 6. EKS POD IDENTITY ASSOCIATION ---

resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    = var.cluster_name
  namespace       = "opencost"
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_pod.arn
}