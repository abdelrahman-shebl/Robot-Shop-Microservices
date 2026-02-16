variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "karpenter_namespace" {
  type    = string
  default = "karpenter"
}

variable "cluster_name" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "controller_role_arn" {
  type = string
}
variable "node_role_name" {
  description = "Karpenter node IAM role name"
  type        = string
}
