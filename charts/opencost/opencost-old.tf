
# --- PART 1: The "Hard" Stuff (Handled by Module) ---
# This module will CREATE the bucket for you.
# Do NOT create a separate resource for this bucket.
module "opencost_aws_setup" {
  source = "" 

  # The Module creates this bucket to store the AWS BILLS
  bucket_name     = "my-company-billing-data-storage-001" 
  
  cur_report_name = "opencost"
  
  # Force Hourly for Spot Accuracy
  time_unit       = "HOURLY"
}

# --- PART 2: The "Easy" Stuff (You handle this) ---
# OpenCost needs a separate bucket to write temporary query results.
# The module does not make this, so we make it here.
resource "aws_s3_bucket" "opencost_results" {
  bucket        = "my-company-opencost-athena-results-001"
  force_destroy = true
}

# --- PART 3: The Cheat Sheet Output ---
# This prints exactly what you need for cloud-integration.json
output "OPENCOST_JSON_VALUES" {
  value = {
    # 1. The Result Bucket (From Part 2)
    athenaBucketName = aws_s3_bucket.opencost_results.bucket
    
    # 2. The Database (Created by the Module)
    athenaDatabase   = module.opencost_aws_setup.cur_database_name
    
    # 3. The Table (Usually matches the report name)
    athenaTable      = "opencost"
    
    # 4. Your Account ID
    projectID        = data.aws_caller_identity.current.account_id
  }
}

# Helper to get Account ID
data "aws_caller_identity" "current" {}
# 2. The IAM Role for Pod Identity (The Authentication)
resource "aws_iam_role" "opencost_role" {
  name = "OpenCostRole"

  # Trust Policy for EKS Pod Identity
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 3. Attach the Permissions from the Module to the Role
resource "aws_iam_role_policy_attachment" "attach_cur_policy" {
  role       = aws_iam_role.opencost_role.name
  # The module automatically creates the perfect policy for us
  policy_arn = module.opencost_aws_setup.iam_policy_arn
}

# --- PART 4: The Association (The Missing Link) ---
# This tells EKS: "When 'opencost' pod starts, give it 'OpenCostRole'"
resource "aws_eks_pod_identity_association" "opencost" {
  cluster_name    = "YOUR_EKS_CLUSTER_NAME" # <--- REPLACE THIS
  
  namespace       = "opencost"
  service_account = "opencost-sa"
  role_arn        = aws_iam_role.opencost_role.arn
}

# --- PART 5: The Output for JSON ---
output "OPENCOST_JSON_CONTENT" {
  value = {
    aws = {
      projectID        = data.aws_caller_identity.current.account_id
      athenaBucketName = aws_s3_bucket.opencost_results.bucket
      athenaDatabase   = module.opencost_aws_setup.cur_database_name
      athenaTable      = "opencost"
      athenaRegion     = "us-east-1"
      usageReport      = "true"
      # No keys needed because of Pod Identity!
    }
  }
}
# make a secret file containing this data
# {
#   "aws": {
#     "projectID": "123456789012",
#     "athenaBucketName": "my-company-opencost-athena-results-prod-001",
#     "athenaDatabase": "athenacurcfn_opencost",
#     "athenaTable": "opencost",
#     "athenaRegion": "us-east-1",
#     "usageReport": "true"
#   }
# }

# # 1. Create the standard namespace
# kubectl create namespace monitoring

# # 2. Add the repo (if you haven't)
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo update

# # 3. Install with your "Easy Config"
# # Release Name: "prom" (Keep this short!)
# helm install prom prometheus-community/kube-prometheus-stack \
#   --namespace monitoring \
#   --values prometheus-easy-config.yaml

# Because of the settings above (fullnameOverride: "monitor" and Release Name: "prom"), your service URL is now practically guaranteed to be:

# http://prom-monitor-prometheus.monitoring.svc:80

#     prom: Your Release Name.

#     monitor: Your Fullname Override.

#     prometheus: The component name.

#     .monitoring: The Namespace.

#     :80: The Port you forced.

# # --- 1. S3 BUCKET: BILLING DATA (The Library) ---
# resource "aws_s3_bucket" "billing_data" {
#   bucket = "my-company-billing-data-prod-001" # CHANGE THIS
#   force_destroy = true
# }

# resource "aws_s3_bucket_policy" "billing_data_policy" {
#   bucket = aws_s3_bucket.billing_data.id
#   policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "billingreports.amazonaws.com"
#       },
#       "Action": [
#         "s3:GetBucketAcl",
#         "s3:GetBucketPolicy",
#         "s3:PutObject"
#       ],
#       "Resource": [
#         "${aws_s3_bucket.billing_data.arn}",
#         "${aws_s3_bucket.billing_data.arn}/*"
#       ]
#     }
#   ]
# }
# POLICY
# }

# # --- 2. S3 BUCKET: ATHENA RESULTS (The Notebook) ---
# resource "aws_s3_bucket" "athena_results" {
#   bucket = "my-company-opencost-results-prod-001" # CHANGE THIS
#   force_destroy = true
# }

# # --- 3. THE REPORT DEFINITION (Telling AWS to write the bill) ---
# resource "aws_cur_report_definition" "opencost_report" {
#   report_name                = "opencost"
#   time_unit                  = "HOURLY" # Critical for Spot
#   format                     = "Parquet" # Critical for Athena
#   compression                = "Parquet"
#   additional_schema_elements = ["RESOURCES"] # Critical for Pod ID matching
#   s3_bucket                  = aws_s3_bucket.billing_data.id
#   s3_region                  = "us-east-1"
#   s3_prefix                  = "reports"
#   report_versioning          = "OVERWRITE_REPORT"
# }

# # --- 4. GLUE & ATHENA (The Database) ---
# resource "aws_glue_catalog_database" "opencost_db" {
#   name = "opencost_db"
# }

# # The Crawler scans Bucket 1 and automatically creates the Table
# resource "aws_glue_crawler" "opencost_crawler" {
#   name          = "opencost_crawler"
#   database_name = aws_glue_catalog_database.opencost_db.name
#   role          = aws_iam_role.glue_crawler_role.arn

#   s3_target {
#     path = "s3://${aws_s3_bucket.billing_data.bucket}/reports/opencost/opencost/"
#   }
# }

# # --- 5. IAM ROLES (Permissions) ---
# # Role for the Glue Crawler to read S3
# resource "aws_iam_role" "glue_crawler_role" {
#   name = "OpenCostGlueCrawlerRole"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Action = "sts:AssumeRole",
#       Effect = "Allow",
#       Principal = { Service = "glue.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "glue_service" {
#   role       = aws_iam_role.glue_crawler_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
# }

# resource "aws_iam_role_policy" "glue_s3_access" {
#   name = "GlueS3Access"
#   role = aws_iam_role.glue_crawler_role.id
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Action = ["s3:GetObject", "s3:PutObject"],
#       Resource = ["${aws_s3_bucket.billing_data.arn}/*"]
#     }]
#   })
# }

# # --- 6. OUTPUTS FOR YOU ---
# output "EXACT_JSON_FOR_OPENCOST" {
#   value = <<EOT
# {
#   "aws": {
#     "usageReport": "true",
#     "projectID": "<YOUR_AWS_ACCOUNT_ID>",
#     "athenaBucketName": "${aws_s3_bucket.athena_results.bucket}",
#     "athenaRegion": "us-east-1",
#     "athenaDatabase": "${aws_glue_catalog_database.opencost_db.name}",
#     "athenaTable": "opencost",
#     "serviceKeyName": "IF_USING_KEYS",
#     "serviceKeySecret": "IF_USING_KEYS"
#   }
# }
# EOT
# }


# [x] Terraform: Created buckets, CUR, IAM Role, and Pod Identity Association.

# [x] Prometheus: Installed with "Easy Config" (Port 80, prom-monitor name).

# [x] Secret: Created cloud-integration secret in opencost namespace.

# [x] Helm: Updated values.yaml with the code above.

# [ ] Action: Run helm install.

# [ ] Action: Import the JSON dashboard into Grafana.