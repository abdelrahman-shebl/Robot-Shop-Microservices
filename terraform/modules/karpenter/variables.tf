variable "cluster_name" {
  type = string
}
variable "queue_name" {
  type = string
}
variable "karpenter_role" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  type = string
}