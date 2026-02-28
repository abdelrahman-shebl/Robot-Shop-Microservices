terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = var.karpenter_namespace
  }
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter/karpenter"
  chart            = "karpenter"
  version          = "1.8.6"   

  namespace        = "karpenter"
  create_namespace = true

  timeout         = 1800       
  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        interruptionQueue = var.queue_name
      }

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.controller_role_arn
        }
      }

      # أضف هنا nodeClass و nodePool زي ما كنت عايز
      nodeClass = {
        default = {
          role = var.node_role_name
          subnetSelectorTerms = [{
            tags = {
              "karpenter.sh/discovery" = var.cluster_name
            }
          }]
          securityGroupSelectorTerms = [{
            tags = {
              "karpenter.sh/discovery" = var.cluster_name
            }
          }]
        }
      }

      nodePool = {
        spot = {
          template = {
            spec = {
              nodeClassRef = { name = "default" }
              requirements = [{
                key      = "karpenter.k8s.aws/capacity-type"
                operator = "In"
                values   = ["spot"]
              }]
            }
          }
          disruption = {
            consolidationPolicy = "WhenUnderutilized"
            consolidateAfter    = "30s"
          }
        }

        ondemand = {
          template = {
            spec = {
              nodeClassRef = { name = "default" }
              requirements = [{
                key      = "karpenter.k8s.aws/capacity-type"
                operator = "In"
                values   = ["on-demand"]
              }]
            }
          }
          disruption = {
            consolidationPolicy = "WhenUnderutilized"
            consolidateAfter    = "30s"
          }
        }
      }
    })
  ]
}

# ──────────────────────────────────────────────────────────────
# EC2NodeClass (مش محتاج yamlencode لو عايز بساطة)
# ──────────────────────────────────────────────────────────────
resource "kubectl_manifest" "default_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: ${var.node_role_name}
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.cluster_name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.cluster_name}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        deleteOnTermination: true
YAML

  depends_on = [helm_release.karpenter]
}

# Spot Pool (الأولوية العالية)
resource "kubectl_manifest" "spot_pool" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  weight: 100
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.k8s.aws/capacity-type
          operator: In
          values: ["spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.medium
            - t3.large
            - c7i.large
            - m7i.large
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    expireAfter: 720h   # 30 يوم
YAML

  depends_on = [kubectl_manifest.default_node_class]
}

# On-Demand fallback (أولوية منخفضة)
resource "kubectl_manifest" "ondemand_pool" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ondemand
spec:
  weight: 10
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.k8s.aws/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.large
            - t3.xlarge
  limits:
    cpu: 50
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    expireAfter: 720h
YAML

  depends_on = [kubectl_manifest.default_node_class]
}

# ──────────────────────────────────────────────────────────────
# Cleanup عند الـ destroy (مهم جدًا)
# ──────────────────────────────────────────────────────────────
resource "terraform_data" "karpenter_cleanup" {
  triggers_replace = {
    id = "cleanup-trigger"
  }

  depends_on = [
    kubectl_manifest.spot_pool,
    kubectl_manifest.ondemand_pool,
    helm_release.karpenter
  ]

  provisioner "local-exec" {
    when = destroy
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      echo "Cleaning up Karpenter resources..."

      kubectl delete nodepool spot ondemand --ignore-not-found --timeout=5m || true

      echo "Terminating any orphaned EC2 instances..."
      INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:karpenter.sh/nodepool,Values=spot,ondemand" \
                  "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[*].Instances[*].InstanceId" --output text)

      if [ -n "$INSTANCE_IDS" ]; then
        echo "Terminating: $INSTANCE_IDS"
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS || true
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS || true
      fi

      echo "Cleanup complete."
    EOT
  }
}