variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "eso_namespace" {
  description = "Namespace to install ESO"
  type        = string
  default     = "eso"
}

variable "chart_version" {
  description = "Optional: ESO Helm chart version"
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "Helm chart repository URL for ESO"
  type        = string
  default     = "https://charts.external-secrets.io"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file for cluster access"
  type        = string
}
