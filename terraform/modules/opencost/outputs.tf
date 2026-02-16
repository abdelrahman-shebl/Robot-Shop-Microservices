output "cloudIntegrationSecret" {
  value = kubernetes_secret.opencost_cloud_integration.metadata[0].name
}