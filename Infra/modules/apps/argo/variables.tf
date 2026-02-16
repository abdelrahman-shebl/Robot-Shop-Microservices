variable "kubeconfig_path" {
  description = "Path to kubeconfig for connecting to EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "helm_version" {
  description = "Optional: specific chart version of ArgoCD"
  type        = string
  default     = ""
}
