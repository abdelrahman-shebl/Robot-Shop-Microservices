variable "name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "service_account" {
  type = string
}

# Policy flags
variable "attach_external_dns_policy" {
  type    = bool
  default = false
}

variable "attach_cert_manager_policy" {
  type    = bool
  default = false
}

variable "attach_external_secrets_policy" {
  type    = bool
  default = false
}

variable "attach_aws_ebs_csi_policy" {
  type    = bool
  default = false
}

variable "hosted_zone_arns" {
  type    = list(string)
  default = []
}

variable "ssm_parameter_arns" {
  type    = list(string)
  default = []
}

variable "create_permission" {
  type    = bool
  default = true
}