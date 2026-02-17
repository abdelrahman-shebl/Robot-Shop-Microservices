terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "terraform_data" "karpenter_node_cleanup" {
  # Tie this resource to the lifecycle of your NodePool
  triggers_replace = {
    nodepool_name = "spot-pool"
  }

  # IMPORTANT: This must depend on the manifest so it exists first.
  # When destroying, Terraform reverses dependencies, so this cleanup 
  # will execute BEFORE the NodePool manifest or Helm chart is destroyed.
  depends_on = [
    kubectl_manifest.karpenter_node_pool_spot
    # Add your Karpenter Helm release here, e.g., helm_release.karpenter
  ]

  provisioner "local-exec" {
    when    = destroy
    # Using bash to execute a graceful delete, followed by a hard AWS EC2 cleanup
    command = <<-EOT
      echo "Attempting graceful teardown of Karpenter NodePool..."
      # 1. Delete the NodePool and wait for Karpenter to drain/terminate nodes
      # (Requires your environment to be configured for kubectl access)
      kubectl delete nodepool spot-pool --ignore-not-found=true --timeout=5m || true
      
      echo "Checking for any orphaned EC2 instances..."
      # 2. Failsafe: Force terminate any EC2 instances still lingering
      # Karpenter tags instances with 'karpenter.sh/nodepool' by default
      INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:karpenter.sh/nodepool,Values=spot-pool" "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text)
        
      if [ -n "$INSTANCE_IDS" ]; then
        echo "Forcefully terminating orphaned Karpenter instances: $INSTANCE_IDS"
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
        
        # Wait a moment for AWS to register the termination
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
        echo "Orphaned instances terminated."
      else
        echo "No orphaned Karpenter instances found. Clean exit."
      fi
    EOT
  }
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version = "1.8.1"

  namespace  = "karpenter"
  create_namespace = true
  
  timeout = 600  # 10 minutes
  wait    = true
  
  values = [
    templatefile("${path.module}/values/karpenter-values.tpl", {
      cluster_name   = var.cluster_name
      queue_name     = var.queue_name
    })
  ]
}


resource "kubectl_manifest" "karpenter_node_class" {
  
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      role = var.karpenter_role
      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      amiFamily = "AL2023"
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = "20Gi"
            volumeType = "gp3"
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

# Spot Priority NodePool (default choice)
resource "kubectl_manifest" "karpenter_node_pool_spot" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: spot-pool
    spec:
      weight: 100  # Higher priority

      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]

            - key: node.kubernetes.io/instance-type 
              operator: In
              values: 
                - "t3.small"
                - "t3.medium"      # Baseline: 1 vCPU, 4GB RAM
                - "t3.large"       # Better baseline: 2 vCPU, 8GB RAM
                - "c7i-flex.large" # Compute optimized: 2 vCPU, 8GB RAM
                - "m7i-flex.large" # Memory opti

            # If a node is draining but pods refuse to leave, 
            # Karpenter will forcefully delete the node after 15 minutes.
            # terminationGracePeriod: 15

      limits:
        cpu: 50
        memory: 200Gi

      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 10s
        expireAfter: 168h
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# On-Demand Fallback NodePool
resource "kubectl_manifest" "karpenter_node_pool_ondemand" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: ondemand-pool
    spec:
      weight: 10  # Lower priority - only used if spot unavailable

      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default

          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]

            - key: node.kubernetes.io/instance-type 
              operator: In
              values: 
                - "t3.large"
                - "t3.xlarge"

      limits:
        cpu: 50
        memory: 200Gi

      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 10s
        expireAfter: 168h
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}