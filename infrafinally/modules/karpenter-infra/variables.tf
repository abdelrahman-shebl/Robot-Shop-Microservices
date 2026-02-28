variable "cluster_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "production"
}

variable "namespace" {
  type    = string
  default = "karpenter"
}

variable "service_account" {
  type    = string
  default = "karpenter-sa"
}

variable "additional_policies" {
  type = map(string)
  default = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}