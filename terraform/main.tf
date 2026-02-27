
module "karpenter_infra" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1" 

  cluster_name =  var.cluster_name 

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
  
  depends_on = [ module.eks ]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name    = var.cluster_name
  kubernetes_version = var.eks_version
  # Disable CloudWatch Log Group creation and cluster logging
  create_cloudwatch_log_group = false
  enabled_log_types           = []

  # Disable KMS Key creation for cluster secret encryption
  create_kms_key            = false
  encryption_config = null
  attach_encryption_policy = false

  # 1. Network Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  # 3. This allows Karpenter nodes to join the cluster security group
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  
  # Cluster security group - allow Karpenter to manage
  create_node_security_group = true
  
  eks_managed_node_groups = {
    karpenter_node_group = {
      create       = true
       name            = "karpenter-node-group"
      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["c7i-flex.large"] 
      capacity_type  = "ON_DEMAND"

      labels = {
        workload-type = "system"
        purpose       = "karpenter-and-control-plane"
      }

      taints = {
        system = {
          key    = "workload-type"
          value  = "system"
          effect = "NO_SCHEDULE"
        }
      }

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
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "workload-type"
            operator = "Equal"
            value    = "system"
            effect   = "NoSchedule"
          }
        ]
      })
    }
    metrics-server = {
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "workload-type"
            operator = "Equal"
            value    = "system"
            effect   = "NoSchedule"
          }
        ]
      })
    }
    metrics-server = {
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "workload-type"
            operator = "Equal"
            value    = "system"
            effect   = "NoSchedule"
          }
        ]
      })
    }

    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_infra.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
      configuration_values = jsonencode({
        controller = {
          tolerations = [
            {
              key      = "workload-type"
              operator = "Equal"
              value    = "system"
              effect   = "NoSchedule"
            }
          ]
        }
      })
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
  source         = "./modules/karpenter"
  queue_name     = module.karpenter_infra.queue_name
  cluster_name   = var.cluster_name
  karpenter_role = module.karpenter_infra.node_iam_role_name
  private_subnet_ids = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  depends_on = [ module.eks ]

}


module "opencost_infra" {
  source       = "./modules/opencost"
  cluster_name = module.eks.cluster_name
  environment  = var.env
  depends_on   = [ module.eks ]
}



module "ssm" {
  source  = "./modules/ssm"
  secrets_map               = local.secrets
  opencost_integration_json = module.opencost_infra.cloud_integration_json
}


module "addons" {
  source                 = "./modules/addons"
  node_role              = module.karpenter_infra.node_iam_role_name
  domain                 = var.domain
  env                    = var.env
  cluster_name           = var.cluster_name
  region                 = var.region
  cloudIntegrationSecret = "cloud-integration"
  depends_on = [ module.eks, module.karpenter_chart_and_crds ]
}


module "zone" {
  source = "terraform-aws-modules/route53/aws"

  name    = var.domain

}


resource "terraform_data" "cleanup_load_balancers" {
  triggers_replace = {
    cluster_name = var.cluster_name
  }

  # This guarantees the script runs BEFORE the ArgoCD apps are destroyed
  depends_on = [
    module.addons
  ]

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting Ingress resources..."
      kubectl delete ingress --all --all-namespaces --ignore-not-found=true --timeout=5m || true
      
      echo "Deleting LoadBalancer Services (Traefik)..."
      kubectl get svc -A | grep LoadBalancer | awk '{print "kubectl delete svc " $2 " -n " $1}' | sh || true
      
      echo "Waiting 45 seconds for AWS Load Balancer Controller to process..."
      sleep 45
    EOT
  }
}



module "external_secrets_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"
  name   = "external-secrets"

  # build the policy with the Get/List/Describe actions
  attach_external_secrets_policy = true

  # Setting these to ["*"] perfectly matches "Resource": ["*"] in your JSON
  # external_secrets_secrets_manager_arns = ["*"]
  external_secrets_ssm_parameter_arns   = module.ssm.parameter_arns
  # external_secrets_kms_key_arns         = ["*"]
  
  # ensure no "CreateSecret" actions are added
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = "${var.cluster_name}"
      namespace       = "eso"
      service_account = "eso-sa"
    }
  }
  depends_on = [ module.eks ]
}

 module "external_dns_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [ module.zone.arn ]
  associations = {
    this = {
      cluster_name    = "${var.cluster_name}"
      namespace       = "edns"
      service_account = "edns-sa"
    }
  }
  depends_on = [ module.eks ]
}

module "cert_manager_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "cert-manager"

  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = [ module.zone.arn ]
  
  associations = {
    this = {
      cluster_name    = "${var.cluster_name}"
      namespace       = "cert-manager"
      service_account = "cert-manager-sa"
    }
  }
  depends_on = [ module.eks ]
} 

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name = "${var.cluster_name}-ebs-csi"

  # Automatically attaches the required permissions for EBS
  attach_aws_ebs_csi_policy = true
}