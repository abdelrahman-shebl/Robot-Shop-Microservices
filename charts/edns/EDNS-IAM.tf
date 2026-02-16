resource "aws_iam_role" "edns_role" {
  name = "edns_role"


  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })


}
resource "aws_iam_policy" "edns-policy" {
  name = "edns-policy"

  policy = file("policies/iam-EDNS.json")
}
resource "aws_iam_role_policy_attachment" "edns-attach" {
  role       = aws_iam_role.edns_role.name
  policy_arn = aws_iam_policy.edns-policy.arn
}

resource "aws_eks_pod_identity_association" "edns_pod_identity_association" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "kube-system"
  service_account = "edns-sa"
  role_arn        = aws_iam_role.edns_role.arn
}
