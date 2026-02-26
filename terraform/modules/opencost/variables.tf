variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "bucket_suffix" {
  description = "Unique suffix for S3 bucket names (must be globally unique)"
  type        = string
  default     = "0022"
}

variable "crawler_schedule" {
  description = "Cron expression for the Glue Crawler schedule (UTC). Default is 1 AM daily."
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}