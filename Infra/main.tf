module "vpc" {
  source = "./modules/networking"
}

module "eks" {
  source = "./modules/eks"
  vpc_id = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  depends_on = [module.vpc]
}

module "argocd" {
  source = "./modules/apps/argo"
  kubeconfig_path = module.eks.kubeconfig_path
  depends_on = [module.eks]
}

module "karpenter" {
  source = "./modules/apps/karpenter"
  cluster_name        = module.eks.cluster_name
  queue_name          = module.karpenter.queue_name
  controller_role_arn = module.karpenter.irsa_arn
  node_role_name      = module.karpenter.node_iam_role_name
}


module "edns" {
  source = "./modules/apps/edns"
  kubeconfig_path = module.eks.kubeconfig_path
  depends_on = [module.eks]
}

module "eso" {
  source = "./modules/apps/eso"
  kubeconfig_path = module.eks.kubeconfig_path
  depends_on = [module.eks]
}

module "opencost" {
  source = "./modules/apps/opencost"

  cluster_name = module.eks.cluster_name

  depends_on = [module.eks]
}

