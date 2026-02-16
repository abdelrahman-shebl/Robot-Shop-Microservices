resource "kubernetes_namespace" "edns" {
  metadata {
    name = var.edns_namespace
  }
}

resource "kubernetes_manifest" "edns_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "external-dns"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        chart          = "external-dns"
        targetRevision = var.chart_version != "" ? var.chart_version : "latest"
        helm = {
          releaseName = "external-dns"
          values      = <<EOF
provider: aws
aws:
  region: eu-central-1
txtOwnerId: "my-cluster"
rbac:
  create: true
resources:
  limits:
    cpu: "200m"
    memory: "256Mi"
EOF
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc" # In-cluster API server URL 
        namespace = var.edns_namespace
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
