output "irsa_arn" {
  value = module.karpenter.iam_role_arn
}

output "node_iam_role_name" {
  value = module.karpenter.node_iam_role_name
}

output "queue_name" {
  value = module.karpenter.queue_name
}
