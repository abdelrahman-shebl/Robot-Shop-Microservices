variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "opencost_namespace" {
  type    = string
  default = "opencost"
}

variable "chart_version" {
  type    = string
  default = "1.43.0"
}
variable "cluster_name" {
  type = string
}
