output "edns_namespace" {
  value = kubernetes_namespace.edns.metadata[0].name
}

output "edns_app_name" {
  value = "external-dns"
}
