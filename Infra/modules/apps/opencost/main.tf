resource "kubernetes_namespace" "opencost" {
  metadata {
    name = var.opencost_namespace
  }
}

resource "kubernetes_manifest" "opencost_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "opencost"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://opencost.github.io/opencost-helm-chart"
        chart          = "opencost"
        targetRevision = var.chart_version
        helm = {
          releaseName = "opencost"
          values = <<EOF
opencost:
  exporter:
    defaultClusterId: ${var.cluster_name}

prometheus:
  enabled: false

service:
  type: ClusterIP

resources:
  limits:
    cpu: "300m"
    memory: "512Mi"
EOF
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.opencost_namespace
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
