module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name            = var.cluster_name
  enable_irsa             = true
  irsa_oidc_provider_arn  = var.oidc_provider_arn
  create_node_iam_role    = true
  create_instance_profile = true
}
