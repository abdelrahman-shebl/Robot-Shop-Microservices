resource "helm_release" "argocd" {
  name       = "argo-cd"
                
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version = "9.4.1"

  namespace  = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/argo-values.tpl", {
      domain = var.domain
    })
  ]
}

resource "helm_release" "argocd-apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version = "2.0.4"
  disable_openapi_validation = true
  depends_on = [ helm_release.argocd ]

  namespace  = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/argo-apps-values.tpl", {
      node_role               = var.node_role
      env                     = var.env
      domain                  = var.domain
      cluster_name            = var.cluster_name
      region                  = var.region
      cloudIntegrationSecret  = var.cloudIntegrationSecret #kubernetes_secret.opencost_cloud_integration.metadata[0].name
    })
  ]
}

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  allow_volume_expansion = true
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type       = "gp3"
    iops       = "3000"
    throughput = "125"
    encrypted  = "true"
  }
}