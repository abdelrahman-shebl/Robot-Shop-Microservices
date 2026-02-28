terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

########################################
# EKS Cluster
########################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  enable_irsa = true

  ########################################
  # EKS Managed Node Groups
  ########################################

  eks_managed_node_groups = {

    ########################################
    # System Nodes (for addons only)
    ########################################
    system = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 2
      max_size       = 3

      labels = {
        workload-type = "system"
      }

      taints = [{
        key    = "workload-type"
        value  = "system"
        effect = "NO_SCHEDULE"
      }]
    }

    ########################################
    # Workload Nodes (apps)
    ########################################
    workload = {
      instance_types = ["t3.large"]
      desired_size   = 2
      min_size       = 1
      max_size       = 5

      labels = {
        workload-type = "application"
      }
    }
  }

  ########################################
  # Cluster Addons
  ########################################

  cluster_addons = {

    ########################################
    # CoreDNS
    ########################################
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [{
          key      = "workload-type"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }]
      })
    }

    ########################################
    # kube-proxy
    ########################################
    kube-proxy = {
      most_recent = true
    }

    ########################################
    # VPC CNI
    ########################################
    vpc-cni = {
      most_recent = true
    }

    ########################################
    # Metrics Server
    ########################################
    metrics-server = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = [{
          key      = "workload-type"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }]
      })
    }

    ########################################
    # EBS CSI Driver
    ########################################
    aws-ebs-csi-driver = {
      most_recent = true

      pod_identity_association = [{
        role_arn        = var.ebs_csi_role_arn
        service_account = "ebs-csi-controller-sa"
      }]

      configuration_values = jsonencode({
        controller = {
          tolerations = [{
            key      = "workload-type"
            operator = "Equal"
            value    = "system"
            effect   = "NoSchedule"
          }]
        }
      })
    }
  }

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# module "eks" {
#   source  = "terraform-aws-modules/eks/aws"
#   version = "~> 20.0" 

#   cluster_name    = "first-eks"
#   cluster_version = "1.29"

#   vpc_id     = var.vpc_id    
#   subnet_ids = var.private_subnets  

#   enable_irsa = true

#   eks_managed_node_groups = {
#     system = {
#       instance_types = ["t3.small"] 
#       min_size       = 2
#       max_size       = 3
#       desired_size   = 2

#       # Node IAM role additional policies
#       iam_role_additional_policies = {
#         AmazonEKS_CNI_Policy                 = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#         AmazonEKSWorkerNodePolicy            = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#         AmazonEC2ContainerRegistryReadOnly   = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#       }
#     }
#   }

#   # API access
#   cluster_endpoint_public_access  = true
#   cluster_endpoint_private_access = false 
# }

# resource "aws_eks_access_entry" "ayman" {
#   cluster_name      = module.eks.cluster_name
#   principal_arn     = "arn:aws:iam::333079845288:user/ayman"
#   type              = "STANDARD"
# }

# resource "aws_eks_access_policy_association" "ayman_admin" {
#   cluster_name  = module.eks.cluster_name
#   principal_arn = aws_eks_access_entry.ayman.principal_arn
#   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#   access_scope {
#     type = "cluster"  # Apply the policy to the entire cluster
#   }
#   depends_on = [ aws_eks_access_entry.ayman ]
# }