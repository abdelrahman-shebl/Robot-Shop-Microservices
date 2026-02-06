resource "aws_iam_role" "karpenter_role" {
  name = "karpenter_role"


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

resource "aws_iam_policy" "karpenter_policy" {
  name = "karpenter-controller-policy-${var.cluster_name}"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "KarpenterScopedInstanceProfileActions",
            "Effect": "Allow",
            "Action": [
                "iam:PassRole",
                "iam:CreateInstanceProfile",
                "iam:TagInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:GetInstanceProfile"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
                    "aws:ResourceTag/karpenter.sh/discovery": "${var.cluster_name}"
                }
            }
        },
        {
            "Sid": "KarpenterScopedEC2InstanceActions",
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:CreateFleet",
                "ec2:CreateLaunchTemplate"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:fleet/*",
                "arn:aws:ec2:*:*:launch-template/*",
                "arn:aws:ec2:*:*:image/*",
                "arn:aws:ec2:*:*:security-group/*",
                "arn:aws:ec2:*:*:subnet/*",
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:network-interface/*",
                "arn:aws:ec2:*:*:instance/*",
                "arn:aws:ec2:*:*:spot-instances-request/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}": "owned"
                },
                "StringLike": {
                    "aws:RequestTag/karpenter.sh/nodepool": "*"
                }
            }
        },
        {
            "Sid": "KarpenterGeneralReadActions",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSpotPriceHistory",
                "ec2:DescribeSubnets"
            ],
            "Resource": "*"
        },
        {
            "Sid": "KarpenterInstanceManagementActions",
            "Effect": "Allow",
            "Action": [
                "ec2:TerminateInstances",
                "ec2:DeleteLaunchTemplate"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned"
                }
            }
        },
        {
            "Sid": "KarpenterSSMActions",
            "Effect": "Allow",
            "Action": "ssm:GetParameter",
            "Resource": "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
        },
        {
            "Sid": "KarpenterPriceListActions",
            "Effect": "Allow",
            "Action": "pricing:GetProducts",
            "Resource": "*"
        },
        {
            "Sid": "KarpenterInterruptionQueueActions",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl",
                "sqs:ReceiveMessage"
            ],

            "Resource": "arn:aws:sqs:*:*:${var.karpenter_sqs_queue_name}"
        }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "karpenter-attach" {
  role       = aws_iam_role.karpenter_role.name
  policy_arn = aws_iam_policy.karpenter_policy.arn
}

resource "aws_eks_pod_identity_association" "karpenter_pod_identity_association" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "karpenter"
  service_account = "karpenter-sa"
  role_arn        = aws_iam_role.karpenter_role.arn
}

#  Add Tags to Subnets (karpenter.sh/discovery).
## "karpenter.sh/discovery" = var.cluster_name
 
#  Create the Node Role (the role for the EC2s, not the controller).

#  Align Namespaces (Decide between karpenter or kube-system).

#  Add the EKS Addon (eks-pod-identity-agent).

#  Handle SQS (Create the queue or remove the policy block).


#######----------------------######
#  don't forget to document the quickest way
# source = "terraform-aws-modules/eks/aws//modules/karpenter"

#   cluster_name = aws_eks_cluster.eks.name

#   # Name of the service account to create in K8s
#   enable_irsa                     = true
#   irsa_oidc_provider_arn          = aws_iam_openid_connect_provider.eks.arn
#   irsa_namespace_service_accounts = ["karpenter:karpenter"]
  # enable_interruption_handling = true
    # 2. Turn ON the new way (Pod Identity)
  # enable_pod_identity             = true
  # create_pod_identity_association = true

  # # 3. Tell AWS which ServiceAccount to watch for
  # namespace       = "karpenter"
  # service_account = "karpenter"
#   # Attach additional permissions to the Node Role (Optional but recommended)
#   node_iam_role_additional_policies = {
#     AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   }

#   tags = {
#     Environment = "dev"
#   }
# }

#######----------------------######