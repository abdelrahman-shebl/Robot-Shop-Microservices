variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "edns_namespace" {
  description = "Namespace to install ExternalDNS"
  type        = string
  default     = "external-dns"
}

variable "chart_version" {
  description = "Optional: ExternalDNS Helm chart version"
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "Helm chart repository URL for ExternalDNS"
  type        = string
  default     = "https://kubernetes-sigs.github.io/external-dns/"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file for cluster access"
  type        = string
}
