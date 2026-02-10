variable "region" {
  default = "us-east-1"
}

variable "domain" {
  default = "shebl22.me"
}
variable "env" {
  default = "dev"
}
variable "cluster_name" {
  default = "eks-robot-shop"
}

variable "eks_version" {
  default = "1.35"
}

locals {
  secrets = yamldecode(file("${path.module}/variables.yaml"))
}