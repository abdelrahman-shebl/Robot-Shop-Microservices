output "cloud_integration_json" {
  description = "The JSON content required for the OpenCost cloud-integration secret"
  value = jsonencode({
    aws = {
      projectID        = data.aws_caller_identity.current.account_id
      athenaBucketName = module.s3_results.s3_bucket_id
      athenaDatabase   = aws_glue_catalog_database.opencost.name
      athenaTable      = "opencost_${var.environment}"
      athenaRegion     = "us-east-1"
      usageReport      = "true"
    }
  })
}