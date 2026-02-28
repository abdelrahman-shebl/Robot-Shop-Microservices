module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"

  name = var.name

  attach_external_dns_policy     = var.attach_external_dns_policy
  attach_cert_manager_policy     = var.attach_cert_manager_policy
  attach_external_secrets_policy = var.attach_external_secrets_policy
  attach_aws_ebs_csi_policy      = var.attach_aws_ebs_csi_policy

  external_dns_hosted_zone_arns  = var.hosted_zone_arns
  cert_manager_hosted_zone_arns  = var.hosted_zone_arns
  external_secrets_ssm_parameter_arns = var.ssm_parameter_arns

  external_secrets_create_permission = var.create_permission

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = var.namespace
      service_account = var.service_account
    }
  }
}