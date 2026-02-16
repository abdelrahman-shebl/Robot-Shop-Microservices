provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

# Namespace for ArgoCD
resource "kubernetes_namespace" "argocd_ns" {
  metadata {
    name = var.namespace
  }
}

# Helm release for ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.helm_version != "" ? var.helm_version : null
  namespace        = var.namespace
  create_namespace = false

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
        }
      }
      controller = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
    })
  ]
}
