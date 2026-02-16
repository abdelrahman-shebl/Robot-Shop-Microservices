variable "private_subnets" {
    description = "List of private subnet IDs for the EKS cluster"
    type        = list(string)
}

variable "vpc_id" {
    description = "VPC ID where the EKS cluster will be deployed"
    type        = string
}

