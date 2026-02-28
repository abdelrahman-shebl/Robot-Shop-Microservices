output "queue_name" {
  value = module.karpenter.queue_name
}

output "node_iam_role_name" {
  value = module.karpenter.node_iam_role_name
}

output "node_iam_role_arn" {
  value = module.karpenter.node_iam_role_arn
}