variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

# Optional dependency (زي eks أو argocd)
variable "depends_on_resources" {
  type    = list(any)
  default = []
}