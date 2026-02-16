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
            volumeSize = "100Gi"
            volumeType = "gp3"
            encrypted  = true
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
                - "t3.medium"      # Baseline: 1 vCPU, 4GB RAM
                - "t3.large"       # Better baseline: 2 vCPU, 8GB RAM
                - "c7i-flex.large" # Compute optimized: 2 vCPU, 8GB RAM
                - "m7i-flex.large" # Memory opti

            # If a node is draining but pods refuse to leave, 
            # Karpenter will forcefully delete the node after 15 minutes.
            # terminationGracePeriod: 15mmized: 2 vCPU, 8GB RAM 

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