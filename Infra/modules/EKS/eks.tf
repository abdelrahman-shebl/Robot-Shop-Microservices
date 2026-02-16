module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" 

  cluster_name    = "first-eks"
  cluster_version = "1.29"

  vpc_id     = var.vpc_id    
  subnet_ids = var.private_subnets  

  enable_irsa = true

  eks_managed_node_groups = {
    system = {
      instance_types = ["t3.small"] 
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      # Node IAM role additional policies
      iam_role_additional_policies = {
        AmazonEKS_CNI_Policy                 = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEKSWorkerNodePolicy            = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEC2ContainerRegistryReadOnly   = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  # API access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false 
}

resource "aws_eks_access_entry" "ayman" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = "arn:aws:iam::333079845288:user/ayman"
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "ayman_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.ayman.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"  # Apply the policy to the entire cluster
  }
  depends_on = [ aws_eks_access_entry.ayman ]
}