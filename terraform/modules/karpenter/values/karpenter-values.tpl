
serviceAccount:
  create: true
  name: "karpenter-sa"

# 2. Global Settings
settings:
  # The name of your EKS Cluster
  clusterName: ${cluster_name}

  # The name of the SQS Queue for Spot Interruptions (Optional but recommended)
  interruptionQueue: ${queue_name}

  # Resources (Karpenter is busy, give it space)
  # It is critical that Karpenter does NOT run on a node it manages (Chicken & Egg).
  # It should run on Fargate or a small static Managed Node Group.
controller:
  resources:
    requests:
      cpu: "500m"
      memory: 1Gi
    limits:
      cpu: 1
      memory: 1Gi
  # Pin Karpenter to the managed node group (CRITICAL: Karpenter must not run on nodes it manages)
  nodeSelector:
    workload-type: "system"

tolerations:
- key: "workload-type"
  operator: "Equal"
  value: "system"
  effect: "NoSchedule"
