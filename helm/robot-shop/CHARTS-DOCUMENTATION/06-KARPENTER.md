# Karpenter - Complete Guide

## Overview

Karpenter is an open-source node auto-scaler for Kubernetes. Unlike the Kubernetes Cluster Autoscaler, Karpenter is designed to be simpler, faster, and more efficient. It automatically scales your cluster based on workload demands.

**Karpenter vs. Cluster Autoscaler:**

```
┌──────────────────────────┬──────────────────────────┐
│ Cluster Autoscaler       │ Karpenter                │
├──────────────────────────┼──────────────────────────┤
│ CloudFormation native    │ Purpose-built for K8s    │
│ Slower (1-2 min scaling) │ Faster (20-30 sec)       │
│ Basic provisioning       │ Smart provisioning       │
│ Reacts to pending pods   │ Predicts future needs    │
│ Manual node groups       │ Auto node pools (NodePool)
│ Works with ASGs          │ Works with EC2 instances │
│ Best for simple setups   │ Best for dynamic workload│
└──────────────────────────┴──────────────────────────┘
```

**Karpenter's key advantages:**
- ✅ Consolidation: Removes unnecessary nodes
- ✅ Speed: Scales in seconds, not minutes
- ✅ Cost-aware: Prefers spot instances, rightsizes
- ✅ Multi-AZ: Distributes across availability zones
- ✅ Expiration handling: Graceful AWS spot interruption handling
- ✅ Custom provisioning: Define exactly what nodes you want

---

## Architecture

```
┌────────────────────────────────────────────────────┐
│         Kubernetes Cluster (EKS)                  │
├────────────────────────────────────────────────────┤
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │  Karpenter Controller                        │ │
│  │  (Runs on dedicated node - Fargate/critical) │ │
│  │                                              │ │
│  │  Watches for:                                │ │
│  │  - Pending pods (Pod status: Pending)        │ │
│  │  - Node pressure (CPU/Memory full)           │ │
│  │  - Consolidation opportunities               │ │
│  └──────────────────────────────────────────────┘ │
│           ↓ When action needed                    │
│  ┌──────────────────────────────────────────────┐ │
│  │  EC2NodeClass (Define node shape)            │ │
│  │  - AMI, instance types, subnet, security... │ │
│  │                                              │ │
│  │  NodePool (Define scaling rules)             │ │
│  │  - Min/max replicas, ttlSeconds, ...        │ │
│  └──────────────────────────────────────────────┘ │
│           ↓ Create nodes matching criteria        │
│  ┌──────────────────────────────────────────────┐ │
│  │  AWS EC2 Instances (Auto-provisioned)       │ │
│  │  - t3.medium, t3.large, m5.large, ...       │ │
│  │  - Spot instances (save 70%)                │ │
│  │  - On-demand fallback                       │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
└────────────────────────────────────────────────────┘
         ↓ AWS CloudTrail logs consolidation/scale events
```

---

## Helm Chart Configuration

### 1. **Basic Enable**

```yaml
karpenter:
  enabled: true

  serviceAccount:
    create: true
    name: "karpenter-sa"
    # Karpenter pod runs as this ServiceAccount
```

---

### 2. **Global Settings**

```yaml
karpenter:
  settings:
    # Name of EKS cluster
    clusterName: "my-cluster"
    
    # SQS Queue for EC2 spot interruption notifications
    interruptionQueue: "Karpenter-Interruption-Queue"
    # When AWS terminates a spot instance, this queue gets notified
    # Karpenter reads it and gracefully drains pods
```

**What the interruption queue does:**

```
Normal spot instance termination (without queue):
┌─ AWS decides to terminate spot instance ─┐
│                                           │
├─ 2-minute warning sent to EC2 metadata   │
├─ BUT: Karpenter might not be listening   │
├─ Pods get killed abruptly                │
└─ Data loss or transaction failures       │

With interruptionQueue (GRACEFUL):
┌─ AWS decides to terminate spot instance ─┐
│                                           │
├─ AWS sends message to SQS queue          │
├─ Karpenter watches queue                 │
├─ Karpenter drains pods gracefully        │
├─ Pods finish processing                  │
├─ Then node terminates cleanly            │
└─ No data loss                            │
```

---

### 3. **Controller Resources**

```yaml
karpenter:
  controller:
    resources:
      requests:
        cpu: "500m"          # Minimum CPU
        memory: 1Gi          # Minimum RAM
      limits:
        cpu: 1               # Maximum CPU
        memory: 1Gi          # Maximum RAM
```

**Why these limits matter:**

```
Karpenter decision tree:
1. Pod pending → Karpenter controller wakes up
2. Analyzes cluster state (CPU, mem, disk usage)
3. Determines optimal EC2 instance type
4. Creates spot instance pricing matrix
5. Launches best instance

This is CPU-intensive work. If Karpenter starves on resources:
- Slow scaling (defeats the purpose)
- Might miss consolidation opportunities
- Could cascade into more scaling

With limits: Karpenter guaranteed resources
```

---

### 4. **Node Selector: Keep Karpenter Safe**

```yaml
karpenter:
  nodeSelector:
    node-role.kubernetes.io/system: "true"
    # Karpenter MUST run on dedicated system node
    # NOT on nodes it manages (chicken & egg problem!)
```

**Critical: Why Karpenter can't run on managed nodes**

```
DANGER: Karpenter running on its own managed node
┌─────────────────────────────────────────────┐
│ Karpenter pod (managing nodes)              │
│ running on Node A (managed by Karpenter)   │
│                                             │
│ Scenario: Consolidation time                │
│ - Karpenter: "Node A is unused, delete it"  │
│ - Karpenter: "Drain Node A..."              │
│ - Karpenter: "Wait, I live on Node A!"      │
│ - Karpenter: "PANIC! Self-terminating..."   │
│ - Cluster: Karpenter crashes!               │
└─────────────────────────────────────────────┘

SOLUTION: Karpenter on system node only
┌─────────────────────────────────────────────┐
│ Karpenter pod (critical system pod)         │
│ running on Node A (tainted: system-only)    │
│                                             │
│ Node B, C, D (managed by Karpenter)        │
│ - User workload pods run here               │
│                                             │
│ Consolidation time:                        │
│ - Karpenter: "Check nodes..."               │
│ - Karpenter: "Node B is unused, delete"     │
│ - Karpenter: "I'm safe on Node A"           │
│ - Karpenter: Cleanup completes cleanly      │
└─────────────────────────────────────────────┘
```

**Taints & tolerations setup:**

```yaml
# Node A (system node - created separately)
apiVersion: v1
kind: Node
metadata:
  labels:
    node-role.kubernetes.io/system: "true"
spec:
  taints:
  - effect: NoSchedule
    key: CriticalAddonsOnly
    value: "true"
    # Only pods with this toleration can run here

# Karpenter pod tolerates this
tolerations:
- key: "CriticalAddonsOnly"
  operator: "Exists"
  effect: "NoSchedule"

# Karpenter nodeSelector ensures it picks system node
nodeSelector:
  node-role.kubernetes.io/system: "true"
```

---

## EC2NodeClass: Defining Node Characteristics

### Overview

EC2NodeClass defines the shape and configuration of EC2 instances Karpenter provisions.

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2                         # Amazon Linux 2
  role: "KarpenterNodeRole-cluster"      # IAM role for nodes
  subnetSelector:
    karpenter.sh/discovery: "true"       # Choose subnets with this tag
  securityGroupSelector:
    karpenter.sh/discovery: "true"       # Choose SGs with this tag
  tags:
    ManagedBy: karpenter                 # Tag all instances
  userData: |
    #!/bin/bash
    # Optional: Custom startup script
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi                # Root volume size
        volumeType: gp3                  # EBS volume type
        deleteOnTermination: true
  metadataOptions:
    httpEndpoint: enabled                # Enable IMDSv2
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
  # Security: Require IMDSv2 token
  #   prevents: SSRF attacks, credential theft
```

### Breaking Down EC2NodeClass

#### 1. **amiFamily**

```yaml
amiFamily: AL2  # Amazon Linux 2
# Other options:
# - UBUNTU: Ubuntu images (no difference for Karpenter)
# - WINDOWS: Windows Server images
# - BOTTLEROCKET: AWS Bottlerocket (lightweight OS)
```

#### 2. **Role: IAM Role for Nodes**

```yaml
role: "KarpenterNodeRole-cluster"
# This IAM role is attached to every node Karpenter creates
# Nodes need this for:
# - Pulling from ECR
# - Writing logs to CloudWatch
# - AWS autoscaling metadata
# - Custom workload permissions
```

**What's in a typical Karpenter node IAM role:**

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}

Attached policies:
- AmazonEKS_CNI_Policy (for networking)
- AmazonEC2ContainerRegistryPowerUser (ECR access)
- AmazonSSMManagedInstanceCore (Systems Manager)
- CloudWatchAgentServerPolicy (CloudWatch logs)
```

#### 3. **Subnet & Security Group Selectors**

```yaml
subnetSelector:
  karpenter.sh/discovery: "true"
  # Karpenter looks for ALL subnets with this tag
  # Randomly picks one for each node

securityGroupSelector:
  karpenter.sh/discovery: "true"
  # Karpenter looks for ALL security groups with this tag
  # Uses them to launch nodes
```

**AWS tagging strategy:**

```hcl
# In Terraform
# Tag all private subnets for Karpenter discovery
resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    "karpenter.sh/discovery" = "true"
    "karpenter.sh/do-not-evict" = "false"  # Allow draining
  }
}

# Tag security group
resource "aws_security_group" "karpenter_nodes" {
  name = "karpenter-nodes"

  tags = {
    "karpenter.sh/discovery" = "true"
  }
}
```

#### 4. **Tags for Tracking**

```yaml
tags:
  ManagedBy: karpenter
  Environment: production
  CostCenter: engineering
  # All instances get these tags
  # Useful for AWS Cost Explorer, billing reports
```

#### 5. **Block Device Mapping (Root Volume)**

```yaml
blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 100Gi           # How big (depends on workload)
      volumeType: gp3             # General purpose (default)
      deleteOnTermination: true   # Clean up when node terminates
      encrypted: true             # (Optional) Encryption at rest
      iops: 3000                  # (Optional) For high I/O workloads
```

**Volume sizing guidance:**

```yaml
# Minimum (most workloads)
volumeSize: 50Gi

# Standard (includes some logs/data)
volumeSize: 100Gi

# Large workloads (GPU, data processing)
volumeSize: 200Gi+
```

#### 6. **Metadata Options (Security)**

```yaml
metadataOptions:
  httpEndpoint: enabled           # Enable EC2 metadata service
  httpProtocolIPv6: disabled      # IPv4 only (standard)
  httpPutResponseHopLimit: 2      # Require IMDSv2 tokens
    # IMDSv2: Prevents SSRF attacks
    # Pods can't get node IAM credentials by making HTTP requests
```

---

## NodePool: Defining Scaling Rules

### Overview

NodePool defines **when** and **how much** Karpenter scales. EC2NodeClass defines **what** kind of nodes.

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:  # What kind of instances to create
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "m5.large"]
        
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
      
      nodeClassRef:
        name: default          # Reference EC2NodeClass
  
  limits:
    cpu: 1000m                # Max total CPU across all nodes
    memory: 1000Gi            # Max total memory
  
  disruption:
    consolidateAfter: 30s     # Wait before consolidation
    expireAfter: 720h         # Node lifespan (30 days)
    budgets:
    - nodes: "10%"            # Only disrupt 10% of nodes at once
```

### Breaking Down NodePool

#### 1. **Requirements: Instance Types**

```yaml
requirements:
  # What architecture?
  - key: kubernetes.io/arch
    operator: In
    values: ["amd64"]  # x86-64, most common
    # alternatives: "arm64" (Apple Silicon, Graviton)
  
  # What OS?
  - key: kubernetes.io/os
    operator: In
    values: ["linux"]
    # alternative: "windows"
  
  # What instance families?
  - key: node.kubernetes.io/instance-type
    operator: In
    values: [
      "t3.medium",    # 1 vCPU, 1 GB RAM - burstable, cheap
      "t3.large",     # 2 vCPU, 8 GB RAM
      "m5.large",     # 2 vCPU, 8 GB RAM - general purpose
      "c5.large",     # 2 vCPU, 4 GB RAM - compute optimized
    ]
  
  # Capacity type (price vs reliability)
  - key: karpenter.sh/capacity-type
    operator: In
    values: [
      "spot",         # 70% cheaper, can be interrupted
      "on-demand",    # Full price, always available
    ]
```

**Instance type selection strategy:**

```yaml
# Strategy 1: Cost-focused (dev/test)
instance-type:
  - t3.micro
  - t3.small
  - t3.medium  # All small/cheap
capacity-type:
  - spot       # Aggressive cost cutting

# Strategy 2: Balanced (production)
instance-type:
  - t3.large
  - m5.large
  - m5.xlarge
capacity-type:
  - spot
  - on-demand  # 80% spot, 20% on-demand for reliability

# Strategy 3: Performance (GPU/ML)
instance-type:
  - g4dn.xlarge    # GPU instances
  - p3.2xlarge     # ML instances
capacity-type:
  - on-demand      # GPUs expensive even spot, so pay full price
```

#### 2. **Limits: Resource Ceiling**

```yaml
limits:
  cpu: 1000m                   # Max 1000 millicores total
  memory: 1000Gi               # Max 1000 GB total
  
  # Example:
  # If running t3.large (2 CPU, 8 GB RAM):
  # - Can launch ~500 nodes before hitting CPU limit
  # - Can launch ~125 nodes before hitting memory limit
  # - Whichever comes first stops scaling!
```

**How limits work:**

```
Scenario: Pending pod needs 500m CPU

1. Karpenter: "Pod needs 500m CPU"
2. Karpenter: "Check limit: cpu: 1000m"
3. Karpenter: "Used so far: 600m"
4. Karpenter: "Available: 1000m - 600m = 400m"
5. Karpenter: "Pod wants 500m, but only 400m available"
6. Karpenter: "Don't provision new node (would exceed limit)"
7. Pod stays pending
8. Team: "Need to increase limits or reduce workload"
```

**Setting limits guidance:**

```yaml
# Small cluster (dev)
limits:
  cpu: 50            # 50 cores max
  memory: 50Gi       # 50 GB max

# Medium cluster (prod-app)
limits:
  cpu: 500           # 500 cores
  memory: 500Gi

# Large cluster (enterprise)
limits:
  cpu: 2000          # 2000 cores
  memory: 2000Gi
```

#### 3. **Disruption: Consolidation & Cleanup**

```yaml
disruption:
  # When to consider consolidation?
  consolidateAfter: 30s
  # Wait 30 seconds after node created before consolidating
  # Prevents thrashing (create/delete/create)
  
  # When to retire nodes?
  expireAfter: 720h
  # After 720 hours (30 days), delete node
  # Forces cycling of nodes (security, OS updates)
  # Recommended: 30 days for production
  
  # How aggressively to consolidate?
  budgets:
  - nodes: "10%"    # Only delete 10% of nodes per disruption event
    # Example: 100 nodes → only 10 deleted at once
    # Keeps cluster stable during consolidation
    
    # Can also specify:
    # - reasons: ["Underutilized"]  # Only consolidate for this reason
    # - nodes: "5"                  # Max 5 nodes, not percentage
    # - duration: "5m"              # 5-minute consolidation window
```

**Disruption reasons:**

```yaml
budgets:
  - reasons:
    - "Underutilized"           # Node <20% utilized
    - "Empty"                   # Node has no pods
    - "UnderutilizedGPU"        # GPU <20% utilized
    nodes: "10%"
```

---

## Complete Example: Production NodePool

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: production
spec:
  # 1. Node template
  template:
    spec:
      requirements:
        # 1a. Architecture
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        
        # 1b. OS
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        
        # 1c. Capacity type (mostly spot, some on-demand)
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
          # Recommendation: Weight spot higher
          # weight: 100 (spot), 10 (on-demand)
        
        # 1d. Instance types (variety for flexibility)
        - key: node.kubernetes.io/instance-type
          operator: In
          values: [
            "t3.large",
            "t3.xlarge",
            "m5.large",
            "m5.xlarge",
            "c5.large",
            "c5.xlarge",
          ]
      
      # 1e. Reference EC2NodeClass
      nodeClassRef:
        name: production
      
      # 1f. Pod affinity (optional but useful)
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values: ["us-east-1a", "us-east-1b"]  # Spread across AZs
  
  # 2. Scaling limits
  limits:
    cpu: 1000               # 1000 cores max
    memory: 1000Gi          # 1000 GB max
  
  # 3. Disruption settings
  disruption:
    consolidateAfter: 30s
    expireAfter: 720h       # 30 days
    budgets:
    - nodes: "10%"          # 10% at a time
      reasons:
      - "Underutilized"
      - "Empty"
    - nodes: "0"            # No disruption during business hours
      schedule: "0 9 * * 1-5"    # Mon-Fri, 9am
      duration: "12h"            # Until 9pm
```

---

## Node Affinity: Preventing Pod-On-Karpenter-Node

### Problem

```
Scenario 1 (GOOD):
┌─ System Node (Karpenter runs here) ─┐
│ - Tainted: CriticalAddonsOnly        │
│ - Only Karpenter pod tolerates taint │
└───────────────────────────────────────┘

Scenario 2 (PROBLEM):
User pod somehow tolerates CriticalAddonsOnly
┌─ System Node ─────────────┐
│ Karpenter pod   ← GOOD   │
│ User pod        ← BAD!   │
│ (sharing = risky)         │
└───────────────────────────┘

Additional Protection Needed!
```

### Solution: Node Affinity

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: user-app
spec:
  # Prevent running on Karpenter system node
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand", "spot"]
            # Only run on Karpenter-managed nodes
            # NOT on system node
  
  containers:
  - name: app
    image: my-app:latest
```

### Alternative: Pod Disruption Budget (PDB)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: critical-app-pdb
spec:
  minAvailable: 1        # Always keep at least 1 pod running
  selector:
    matchLabels:
      app: critical-payment
      # Karpenter won't drain this pod without replacement
```

---

## Required AWS Infrastructure

### 1. **IAM Roles & Policies**

Karpenter needs permissions to:
- Create/terminate EC2 instances
- Manage security groups
- Read subnet/AZ information
- Handle spot instance interruptions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateFleet",
        "ec2:CreateInstances",
        "ec2:CreateTags",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeImages",
        "ec2:GetSpotPriceHistory",
        "ec2:RunInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. **Spot Interruption Queue (SQS)**

Required for graceful spot instance termination handling.

```hcl
# Terraform
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "Karpenter-Interruption-Queue"
  message_retention_seconds = 60
}

# Event bridge rule to notify queue on spot termination
resource "aws_cloudwatch_event_rule" "spot_termination" {
  name        = "karpenter-spot-termination"
  description = "Notify Karpenter of spot interruptions"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  rule      = aws_cloudwatch_event_rule.spot_termination.name
  target_id = "KarpenterQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}
```

### 3. **Subnet & Security Group Tagging**

Required for Karpenter to find where to launch nodes.

```hcl
# Tag subnets
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    "karpenter.sh/discovery" = "true"
    Name                     = "private-subnet-1a"
  }
}

# Tag security group
resource "aws_security_group" "karpenter_nodes" {
  name = "karpenter-nodes"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # Allow from VPC
  }

  tags = {
    "karpenter.sh/discovery" = "true"
  }
}
```

---

## Terraform Module: Simplified Setup

```hcl
# Use terraform-aws-modules/eks/aws//modules/karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1" # Latest version as of Feb 2026

  cluster_name = aws_eks_cluster.main.name

  # --- Pod Identity Configuration ---
  # This replaces the need for 'irsa_oidc_provider_arn'
  enable_pod_identity             = true
  create_pod_identity_association = true
  
  # Defines which Kubernetes Service Account gets the permissions
  namespace       = "karpenter"
  service_account = "karpenter"

  # --- Node Role Configuration ---
  # This IAM role is attached to the actual EC2 instances Karpenter creates.
  # We add SSM permissions so you can shell into nodes for debugging.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "production"
  }
}

output "karpenter_role_arn" {
  value = module.karpenter.irsa_arn
}
```

**Module handles:**
- ✅ IRSA setup
- ✅ IAM policies
- ✅ Helm chart deployment
- ✅ RBAC configuration
- ✅ CRD installation

---

## Node Group Configuration

### Keep Karpenter Isolated

```hcl
# Static node group for Karpenter (must not be managed by Karpenter!)
resource "aws_eks_node_group" "karpenter_system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "karpenter-system"
  node_role_arn   = aws_iam_role.node.arn

  scaling_config {
    desired_size = 2        # Always have 2 system nodes for HA
    max_size     = 3
    min_size     = 2
  }

  instance_types = ["t3.medium"]  # Small, cheap nodes

  labels = {
    "node-role.kubernetes.io/system" = "true"
  }

  taints {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name = "Karpenter System Nodes"
  }
}
```

---

## Complete Karpenter Setup Example

```yaml
---
# 1. EC2NodeClass: Define node characteristics
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: production
spec:
  amiFamily: AL2
  role: "KarpenterNodeRole-cluster"
  subnetSelector:
    karpenter.sh/discovery: "true"
  securityGroupSelector:
    karpenter.sh/discovery: "true"
  tags:
    ManagedBy: karpenter
    Environment: production
  userData: |
    #!/bin/bash
    echo "Karpenter provisioned node" > /var/log/karpenter-setup.log
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        deleteOnTermination: true
        encrypted: true
  metadataOptions:
    httpEndpoint: enabled
    httpPutResponseHopLimit: 2

---
# 2. NodePool: Define scaling rules
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: production
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]
        
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
      
      nodeClassRef:
        name: production
  
  limits:
    cpu: 1000m
    memory: 1000Gi
  
  disruption:
    consolidateAfter: 30s
    expireAfter: 720h
    budgets:
    - nodes: "10%"
```

---

## Troubleshooting

### Problem: Pods staying pending

```bash
# Check Karpenter logs
kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter

# Check pending pods
kubectl get pods --field-selector=status.phase=Pending

# Check EC2NodeClass exists
kubectl get ec2nodeclass

# Check NodePool exists
kubectl get nodepools
```

### Problem: Nodes not consolidating

```bash
# Check disruption budget
kubectl get pdb

# Check node consolidation events
kubectl describe nodeclaim <node-name> | grep Events

# Verify consolidation settings
kubectl get nodepools -o yaml | grep -A 10 disruption
```

### Problem: "Unable to assume role"

```bash
# Verify Pod Identity association
aws eks describe-pod-identity-association \
  --cluster-name my-cluster
```

---

## Production Checklist

- [ ] System node group created (separate from Karpenter)
- [ ] Karpenter IAM role created (use Pod Identity)
- [ ] EC2NodeClass defined correctly
- [ ] NodePool limits set appropriately
- [ ] Subnets tagged with `karpenter.sh/discovery: true`
- [ ] Security groups tagged with `karpenter.sh/discovery: true`
- [ ] SQS queue for spot interruptions created
- [ ] EventBridge rule for spot notifications
- [ ] Test with simple test pod
- [ ] Monitor Karpenter logs for errors
- [ ] Set up cost monitoring (CloudWatch, AWS Cost Explorer)

---

## Reference

- [Karpenter Documentation](https://karpenter.sh/)
- [Karpenter AWS Provider](https://karpenter.sh/docs/concepts/provisioners/#aws)
- [EC2NodeClass Reference](https://karpenter.sh/docs/concepts/node-classes/#ec2nodeclass)
- [Terraform AWS Modules - Karpenter](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/main/modules/karpenter)
