output "eso_namespace" {
  value = kubernetes_namespace.eso.metadata[0].name
}

output "eso_app_name" {
  value = "eso"
}
