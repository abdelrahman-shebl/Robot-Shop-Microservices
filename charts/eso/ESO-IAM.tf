resource "aws_iam_role" "eso" {
  name = "eso-role"

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
      }
    ]
  })
}

resource "aws_iam_policy" "eso-policy" {
  name        = "eso-policy"

  policy = file("policies/iam_eso.json")
}

resource "aws_iam_role_policy_attachment" "eso-attach" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso-policy.arn
}

resource "aws_eks_pod_identity_association" "eso_pod_identity_association" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "eso"
  service_account = "eso-sa"
  role_arn        = aws_iam_role.eso.arn
}
