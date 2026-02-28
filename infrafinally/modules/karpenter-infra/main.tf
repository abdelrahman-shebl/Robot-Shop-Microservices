module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1"

  cluster_name = var.cluster_name

  create_pod_identity_association = true

  namespace       = var.namespace
  service_account = var.service_account

  node_iam_role_additional_policies = var.additional_policies

  tags = {
    Environment = var.environment
  }
}