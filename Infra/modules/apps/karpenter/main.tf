resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = var.karpenter_namespace
  }
}

resource "kubernetes_manifest" "karpenter_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "karpenter"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://charts.karpenter.sh"
        chart          = "karpenter"
        targetRevision = "v0.37.0"
        helm = {
          releaseName = "karpenter"
          values = <<EOF
settings:
  clusterName: ${var.cluster_name}
  interruptionQueue: ${var.queue_name}

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${var.controller_role_arn}

controller:
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"
EOF
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.karpenter_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "karpenter_nodeclass" {
  depends_on = [kubernetes_manifest.karpenter_app]

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name      = "default"
      namespace = var.karpenter_namespace
    }
    spec = {
      role = var.node_role_name

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
    }
  }
}


resource "kubernetes_manifest" "karpenter_spot_pool" {
  depends_on = [kubernetes_manifest.karpenter_nodeclass]

  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "spot"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            name = "default"
          }
          requirements = [
            {
              key      = "karpenter.k8s.aws/capacity-type"
              operator = "In"
              values   = ["spot"]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "karpenter_ondemand_pool" {
  depends_on = [kubernetes_manifest.karpenter_nodeclass]

  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "ondemand"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            name = "default"
          }
          requirements = [
            {
              key      = "karpenter.k8s.aws/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }
    }
  }
}
