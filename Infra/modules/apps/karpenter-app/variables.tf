variable "cluster_name"        { type = string }
variable "queue_name"          { type = string }
variable "controller_role_arn" { type = string }
variable "node_role_name"      { type = string }
variable "karpenter_namespace" {
  type        = string
  description = "Namespace for Karpenter installation"
  default     = "karpenter"
}