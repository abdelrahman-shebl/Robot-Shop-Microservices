
module "karpenter_infra" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1" 

  cluster_name = var.cluster_name


  create_pod_identity_association = true
  
  namespace       = "karpenter"
  service_account = "karpenter-sa"

  # --- Node Role Configuration ---

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "production"
  }
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name    = var.cluster_name
  kubernetes_version = var.eks_version

  # 1. Network Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  # 3. ADDED: This allows Karpenter nodes to join the cluster security group
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  eks_managed_node_groups = {
    karpenter_node_group = {
       name            = "karpenter-node-group"
      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["c7i-flex.large"]
      capacity_type  = "ON_DEMAND"


  # labels = {
  #   Environment = "test"
  #   GithubRepo  = "terraform-aws-eks"
  #   GithubOrg   = "terraform-aws-modules"
  # }

  # taints = {
  #   dedicated = {
  #     key    = "dedicated"
  #     value  = "gpuGroup"
  #     effect = "NO_SCHEDULE"
  #   }
  # }

    }
  }

  endpoint_public_access  = true
  endpoint_private_access = false

  # 2. Access & Authentication
  authentication_mode = "API"

  enable_cluster_creator_admin_permissions = true

  # 3. Addons
    addons = {
    eks-pod-identity-agent = {
      addon_version = "v1.3.4-eksbuild.1"
    }
  }

}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "robot-shop-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true

 public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
  }

    private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "karpenter.sh/discovery"                    = "${var.cluster_name}"
  }

}




module "karpenter_chart_and_crds" {
  source  = "./modules/karpenter"
  queue_name             = module.karpenter_infra.queue_name
  cluster_name           = var.cluster_name
  karpenter_role         = module.karpenter_infra.iam_role_name

}


module "opencost_infra" {
  source  = "./modules/opencost"
  cluster_name = var.cluster_name
}
module "edns_infra" {
  source  = "./modules/edns"
  cluster_name = var.cluster_name
}
# add eso files
module "eso_fra" {
  source  = "./modules/eso"
  cluster_name = var.cluster_name
}
module "ssm" {
  source  = "./modules/ssm"
  # MySQL Root Credentials
  MYSQL_ROOT_PASSWORD = local.secrets.MYSQL_ROOT_PASSWORD

  # Shipping MySQL Credentials
  SHIPPING_MYSQL_USER = local.secrets.SHIPPING_MYSQL_USER
  SHIPPING_MYSQL_PASSWORD = local.secrets.SHIPPING_MYSQL_PASSWORD
  SHIPPING_MYSQL_DATABASE = local.secrets.SHIPPING_MYSQL_DATABASE

  # Ratings MySQL Credentials
  RATINGS_MYSQL_USER = local.secrets.RATINGS_MYSQL_USER
  RATINGS_MYSQL_PASSWORD = local.secrets.RATINGS_MYSQL_PASSWORD
  RATINGS_MYSQL_DATABASE = local.secrets.RATINGS_MYSQL_DATABASE
  

  # MongoDB Root Credentials
  MONGO_INITDB_ROOT_USERNAME = local.secrets.MONGO_INITDB_ROOT_USERNAME
  MONGO_INITDB_ROOT_PASSWORD = local.secrets.MONGO_INITDB_ROOT_PASSWORD
  # Catalog MongoDB Credentials
  CATALOGUE_MONGO_USER = local.secrets.CATALOGUE_MONGO_USER
  CATALOGUE_MONGO_PASSWORD = local.secrets.CATALOGUE_MONGO_PASSWORD
  CATALOGUE_MONGO_DATABASE = local.secrets.CATALOGUE_MONGO_DATABASE

  # Users MongoDB Credentials
  USER_MONGO_USER = local.secrets.USER_MONGO_USER
  USER_MONGO_PASSWORD = local.secrets.USER_MONGO_PASSWORD
  USER_MONGO_DATABASE = local.secrets.USER_MONGO_DATABASE

# Dojo Credentials
  DD_ADMIN_USER = local.secrets.DD_ADMIN_USER
  DD_ADMIN_PASSWORD = local.secrets.DD_ADMIN_PASSWORD
}


module "addons" {
  source  = "./modules/addons"
  node_role              = module.karpenter_infra.node_iam_role_name
  domain                 = var.domain
  env                     = var.env
  cluster_name           = var.cluster_name
  region                 = var.region
  cloudIntegrationSecret = module.opencost_infra.cloudIntegrationSecret
}


module "zone" {
  source = "terraform-aws-modules/route53/aws"

  name    = var.domain

}



# module "eks_managed_node_group" {
#   source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
#   version = "21.15.1"

#   name            = "karpenter-node-group"
#   cluster_name    = var.cluster_name
#   subnet_ids = module.vpc.private_subnets

#   cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
#   vpc_security_group_ids            = [module.eks.node_security_group_id]


#   min_size     = 1
#   max_size     = 2
#   desired_size = 1

#   instance_types = ["c7i-flex.large"]
#   capacity_type  = "ON_DEMAND"


# }
