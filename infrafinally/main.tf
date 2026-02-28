module "eks" {
  source = "./modules/eks"

  cluster_name     = var.cluster_name
  cluster_version  = "1.29"
  vpc_id           = module.vpc.vpc_id
  private_subnets  = module.vpc.private_subnets
  environment      = var.environment 
  ebs_csi_role_arn = module.ebs_csi.iam_role_arn
}

module "vpc" {
  source = "./modules/vpc"

  name = "robot-shop-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  cluster_name      = var.cluster_name
  environment       = var.environment
  enable_nat_gateway = true
}

module "external_dns" {
  source          = "./modules/pod-identity"
  name            = "external-dns"
  cluster_name    = var.cluster_name
  namespace       = "edns"
  service_account = "edns-sa"

  attach_external_dns_policy = true
  hosted_zone_arns           = [module.zone.arn]

  depends_on = [module.eks]
}

module "cert_manager" {
  source          = "./modules/pod-identity"
  name            = "cert-manager"
  cluster_name    = var.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager-sa"

  attach_cert_manager_policy = true
  hosted_zone_arns           = [module.zone.arn]

  depends_on = [module.eks]
}

module "external_secrets" {
  source          = "./modules/pod-identity"
  name            = "external-secrets"
  cluster_name    = var.cluster_name
  namespace       = "eso"
  service_account = "eso-sa"

  attach_external_secrets_policy = true
  ssm_parameter_arns             = module.ssm.parameter_arns
  create_permission              = false

  depends_on = [module.eks]
}

module "ebs_csi" {
  source          = "./modules/pod-identity"
  name            = "${var.cluster_name}-ebs-csi"
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"

  attach_aws_ebs_csi_policy = true

  depends_on = [module.eks]
}

module "cluster_destroy_cleanup" {
  source       = "./modules/cluster-destroy-cleanup"
  cluster_name = var.cluster_name
  region       = var.region

  depends_on_resources = [
    module.eks,
    module.argocd  
  ]
}

module "karpenter_infra" {
  source       = "./modules/karpenter-infra"
  cluster_name = var.cluster_name
  environment  = var.env

  depends_on = [module.eks]
}

module "karpenter_chart_and_crds" {
  source         = "./modules/karpenter"
  queue_name     = module.karpenter_infra.queue_name
  cluster_name   = var.cluster_name
  karpenter_role = module.karpenter_infra.node_iam_role_name
  private_subnet_ids = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  depends_on = [
    module.eks,
    module.karpenter_infra
  ]

}


module "opencost_infra" {
  source       = "./modules/opencost"
  cluster_name = module.eks.cluster_name
  depends_on = [ module.eks ]
}


module "ssm" {
  source  = "./modules/ssm"
# Pass the entire map at once!
  secrets_map = local.secrets
}


module "argocd" {
  source                 = "./modules/argocd"
  node_role              = module.karpenter_infra.node_iam_role_name
  domain                 = var.domain
  env                    = var.env
  cluster_name           = var.cluster_name
  region                 = var.region
  cloudIntegrationSecret = module.opencost_infra.cloudIntegrationSecret
  depends_on = [ module.eks, module.karpenter_chart_and_crds ]
}


module "zone" {
  source = "terraform-aws-modules/route53/aws"

  name    = var.domain

}
