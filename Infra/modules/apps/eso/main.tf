resource "kubernetes_namespace" "eso" {
  metadata {
    name = var.eso_namespace
  }
}

resource "kubernetes_manifest" "eso_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1" 
    kind       = "Application" # ArgoCD Application 
    metadata = {
      name      = "eso"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        chart          = "external-secrets"
        targetRevision = var.chart_version != "" ? var.chart_version : "latest"
        helm = {
          releaseName = "eso"
          values      = <<EOF
controller:
  resources:
    limits:
      cpu: "300m"
      memory: "512Mi"
EOF
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.eso_namespace
      }
      syncPolicy = {
        automated = {
          prune = true # Automatically delete resources that are no longer defined in the Git repository
          selfHeal = true # Automatically revert changes made to the cluster that deviate from the Git repository
        }
      }
    }
  }
}
