# Karpenter: NodePool and EC2NodeClass Deep Reference

Companion file:
- [Karpenter.md](Karpenter.md)

---

## 1) The Two Objects

Karpenter uses two CRDs to define how and where nodes are launched:

| Object          | Purpose                                                                |
|-----------------|------------------------------------------------------------------------|
| `EC2NodeClass`  | Defines the AWS-level node configuration (AMI, subnets, security groups, disk, IAM role) |
| `NodePool`      | Defines the workload-level scheduling policy (capacity type, instance types, limits, disruption) |

A `NodePool` references an `EC2NodeClass`. The NodePool decides *when* to launch a node and *what kind* of workload it accepts. The EC2NodeClass decides *how* to launch it in AWS.

---

## 2) EC2NodeClass

### What it controls

- Which AMI to use (Amazon Linux 2023, Bottlerocket, custom),
- which subnets to launch into,
- which security groups to attach,
- what IAM role to assign to the node,
- what block device (disk) settings to apply,
- user data and custom instance startup scripts.

---

### Full EC2NodeClass with all fields explained

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:

  # --- IAM Role ---
  # The IAM role name to assign to the EC2 instance profile.
  # This is the node role created by karpenter_infra module.
  # Nodes use this role to interact with ECR, SSM, and join the cluster.
  role: "KarpenterNodeRole-my-cluster"

  # --- AMI Selection ---
  # How Karpenter chooses the Amazon Machine Image for new nodes.
  # Option A: Use an alias (simplest, always gets the latest patched AMI)
  amiSelectorTerms:
    - alias: "al2023@latest"      # Amazon Linux 2023, always latest
    # - alias: "bottlerocket@latest"  # Bottlerocket OS (container-optimized)
    # - alias: "al2@latest"           # Amazon Linux 2 (legacy)

  # Option B: Pick by name pattern (pin to a specific AMI family)
  # amiSelectorTerms:
  #   - name: "amazon-eks-node-al2023-x86_64-standard-1.31-*"

  # Option C: Pin to a specific AMI by ID (no auto-update)
  # amiSelectorTerms:
  #   - id: "ami-0abcdef1234567890"

  # amiFamily must match the AMI type chosen above
  amiFamily: AL2023          # AL2023 | AL2 | Bottlerocket | Custom | Windows2019 | Windows2022

  # --- Subnet Selection ---
  # How Karpenter finds which subnets to launch nodes into.
  # Option A: By tag (recommended — matches the karpenter.sh/discovery tag on subnets)
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "my-cluster"

  # Option B: List exact subnet IDs (useful when Terraform injects them)
  # subnetSelectorTerms:
  #   - id: "subnet-0abc123"
  #   - id: "subnet-0def456"

  # --- Security Group Selection ---
  # Which security groups to attach to launched nodes.
  # Must include the cluster node security group so nodes can communicate.
  # Option A: By tag
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "my-cluster"

  # Option B: By ID (Terraform injects this)
  # securityGroupSelectorTerms:
  #   - id: "sg-0abc1234"

  # --- Block Device (Disk) ---
  # Root volume configuration for all nodes launched with this class.
  blockDeviceMappings:
    - deviceName: /dev/xvda       # root device for AL2023 / AL2
      ebs:
        volumeSize: 20Gi          # disk size (increase for image-heavy workloads)
        volumeType: gp3           # gp3 is cheaper and faster than gp2
        iops: 3000                # only applies to gp3 (baseline: 3000)
        throughput: 125           # MiB/s (baseline: 125)
        encrypted: true           # encrypt the volume at rest
        deleteOnTermination: true # clean up disk when node is terminated

  # --- User Data ---
  # Shell script injected into EC2 instance metadata at launch.
  # Runs before the kubelet starts.
  # userData: |
  #   #!/bin/bash
  #   echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  #   sysctl -p

  # --- Instance Metadata Service ---
  # IMDSv2 forces all metadata requests to use a session token (more secure)
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1     # 1 = only the node itself can call IMDS (no containers)
    httpTokens: required           # enforces IMDSv2
```

---

### Minimal EC2NodeClass (what you actually need)

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-my-cluster"
  amiSelectorTerms:
    - alias: "al2023@latest"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "my-cluster"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "my-cluster"
  amiFamily: AL2023
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
```

---

### EC2NodeClass with Terraform-injected subnet and SG IDs

When Terraform manages the infrastructure, it is cleaner to inject exact IDs rather than relying on tag discovery:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${cluster_name}"    # Terraform injects cluster_name
  amiSelectorTerms:
    - alias: "al2023@latest"
  amiFamily: AL2023
  subnetSelectorTerms:
    - id: "subnet-0abc123"    # injected from module.vpc.private_subnets[0]
    - id: "subnet-0def456"    # injected from module.vpc.private_subnets[1]
  securityGroupSelectorTerms:
    - id: "sg-0abc1234"       # injected from module.eks.node_security_group_id
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
```

In Terraform, this is done with `yamlencode()` which builds the YAML from HCL variables:

```hcl
subnetSelectorTerms = [
  for subnet_id in var.private_subnet_ids : {
    id = subnet_id
  }
]
securityGroupSelectorTerms = [
  { id = var.node_security_group_id }
]
```

---

## 3) NodePool

### What it controls

- Which capacity type to use (spot, on-demand),
- which instance types are allowed,
- which architectures are allowed (amd64, arm64),
- minimum/maximum resource limits for all nodes in this pool,
- how and when to consolidate (remove underutilized nodes),
- when to expire nodes (force rotation after N hours),
- weight for multi-pool priority,
- node labels and taints to apply to launched nodes.

---

### Full NodePool with all fields explained

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-pool
spec:

  # --- Priority Weight ---
  # When multiple NodePools exist, Karpenter picks the one with the highest weight first.
  # Range: 1–100. Higher = tried first.
  weight: 100

  # --- Node Template ---
  template:
    metadata:
      # Labels are applied to every node launched from this NodePool.
      # Pods can use nodeSelector to target specific pools.
      labels:
        pool-type: spot
        workload: general

      # Taints applied to launched nodes.
      # Use to dedicate a pool to specific workloads.
      # taints:
      #   - key: dedicated
      #     value: gpu
      #     effect: NoSchedule

    spec:
      # Which EC2NodeClass configuration to use for this pool
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      # --- Requirements ---
      # Constraints on what kind of nodes to launch.
      # Each requirement must be satisfied for a node to be selected.
      requirements:

        # Architecture: amd64 (x86) or arm64 (Graviton)
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        # OS: linux or windows
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Capacity type: spot or on-demand
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
          # Use ["spot", "on-demand"] to allow both (Karpenter prefers spot automatically)

        # Availability zone restriction (optional)
        # - key: topology.kubernetes.io/zone
        #   operator: In
        #   values: ["us-east-1a", "us-east-1b"]

        # Instance type allowlist
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.small
            - t3.medium
            - t3.large
            - c7i-flex.large
            - m7i-flex.large
          # Use NotIn to block specific instance types instead:
          # operator: NotIn
          # values: ["t2.micro", "t2.small"]

        # Instance category: general purpose, compute, memory, accelerator, etc.
        # - key: karpenter.k8s.aws/instance-category
        #   operator: In
        #   values: ["c", "m", "r"]   # c=compute, m=general, r=memory

        # Instance generation (avoid very old generations)
        # - key: karpenter.k8s.aws/instance-generation
        #   operator: Gt             # Gt = greater than
        #   values: ["2"]

        # GPU instances: require or exclude
        # - key: karpenter.k8s.aws/instance-gpu-count
        #   operator: Gt
        #   values: ["0"]            # require at least 1 GPU

      # --- Node Startup Tolerance ---
      # Maximum time Karpenter waits for a node to become Ready before giving up
      # and trying another instance type. Default: 20m
      # startupTaints are removed when the node is ready (used for initialization)
      # startupTaints:
      #   - key: node.cloudprovider.kubernetes.io/uninitialized
      #     effect: NoSchedule

  # --- Resource Limits ---
  # Maximum total resources across ALL nodes in this NodePool.
  # Karpenter stops launching nodes once these are reached.
  # This caps the blast radius of runaway scaling.
  limits:
    cpu: 50           # 50 vCPUs total across this pool
    memory: 200Gi     # 200Gi total RAM across this pool

  # --- Disruption Policy ---
  # Controls how Karpenter removes or replaces nodes.
  disruption:

    # consolidationPolicy:
    #   WhenEmpty            - only remove nodes with no pods
    #   WhenEmptyOrUnderutilized - also consolidate underused nodes (bin-packing)
    consolidationPolicy: WhenEmptyOrUnderutilized

    # How long to wait after a node becomes empty/underutilized before removing it.
    # Short values (10s) save cost fast but cause more churn.
    # Longer values (5m) are more stable.
    consolidateAfter: 30s

    # Maximum node lifetime before Karpenter replaces it.
    # Forces node rotation to pick up OS patches and AMI updates.
    # Karpenter drains the node gracefully before terminating.
    # 168h = 7 days. Set to Never to disable expiry.
    expireAfter: 168h

    # Budget: limits how many nodes can be disrupted at once.
    # Prevents Karpenter from draining too many nodes simultaneously.
    budgets:
      - nodes: "10%"          # maximum 10% of nodes disrupted at once
      # - nodes: "1"          # or an absolute count
      # Schedule-based budget (no disruption during business hours):
      # - schedule: "0 9 * * 1-5"     # 9 AM Monday-Friday
      #   duration: 8h                 # block disruption for 8 hours
      #   nodes: "0"                   # 0 nodes allowed to be disrupted
```

---

### NodePool Requirements: Operators Reference

| Operator | Meaning                                     | Example                                      |
|----------|---------------------------------------------|----------------------------------------------|
| `In`     | value must be in the list                   | `values: ["spot"]`                           |
| `NotIn`  | value must NOT be in the list               | `values: ["t2.micro"]`                       |
| `Exists` | key must exist (any value)                  | no `values` needed                           |
| `DoesNotExist` | key must not exist                    | no `values` needed                           |
| `Gt`     | value must be greater than (numeric string) | `values: ["2"]` (generation > 2)             |
| `Lt`     | value must be less than (numeric string)    | `values: ["32"]` (vCPU count < 32)           |

---

### NodePool Well-Known Keys Reference

| Key                                          | What it filters                             |
|----------------------------------------------|---------------------------------------------|
| `kubernetes.io/arch`                         | CPU architecture: `amd64`, `arm64`          |
| `kubernetes.io/os`                           | OS: `linux`, `windows`                      |
| `karpenter.sh/capacity-type`                 | `spot` or `on-demand`                       |
| `node.kubernetes.io/instance-type`           | Exact EC2 instance type names               |
| `topology.kubernetes.io/zone`                | Availability zone                           |
| `karpenter.k8s.aws/instance-category`        | `c` (compute), `m` (general), `r` (memory), `g` (GPU) |
| `karpenter.k8s.aws/instance-generation`      | Generation number (integer as string)       |
| `karpenter.k8s.aws/instance-cpu`             | vCPU count                                  |
| `karpenter.k8s.aws/instance-memory`          | Memory in MiB                               |
| `karpenter.k8s.aws/instance-gpu-count`       | Number of GPUs                              |
| `karpenter.k8s.aws/instance-gpu-manufacturer`| `nvidia`, `amd`                             |
| `karpenter.k8s.aws/instance-network-bandwidth`| Network bandwidth in Mbps                  |

---

## 4) Common NodePool Patterns

### Pattern A: Spot-only pool (cost-optimized)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-pool
spec:
  weight: 100
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.medium
            - t3.large
            - c7i-flex.large
            - m7i-flex.large
  limits:
    cpu: 50
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    expireAfter: 168h
```

---

### Pattern B: On-demand fallback pool (low priority)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ondemand-pool
spec:
  weight: 10    # lower = used only when spot unavailable
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.large
            - t3.xlarge
  limits:
    cpu: 50
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    expireAfter: 168h
```

Karpenter tries `spot-pool` (weight 100) first. If no spot capacity is available, it falls back to `ondemand-pool` (weight 10).

---

### Pattern C: Mixed spot + on-demand in a single pool

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot", "on-demand"]   # Karpenter prefers spot, uses on-demand if unavailable
```

Simpler than two pools, but gives less control over on-demand usage limits.

---

### Pattern D: Compute-optimized pool (for CPU-heavy workloads)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: compute-pool
spec:
  weight: 80
  template:
    metadata:
      labels:
        workload: compute-intensive
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      # Apply a taint so only pods with matching tolerations land here
      taints:
        - key: dedicated
          value: compute
          effect: NoSchedule
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c"]        # compute-optimized family only (c5, c6i, c7i, etc.)
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]        # only gen 6+ (c6i, c7i)
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["4", "8", "16"]   # only 4, 8, or 16 vCPU sizes
  limits:
    cpu: 100
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    expireAfter: 72h
```

Pods targeting this pool must have the matching toleration:
```yaml
tolerations:
  - key: dedicated
    value: compute
    effect: NoSchedule
```

---

### Pattern E: Memory-optimized pool (for databases, caches)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: memory-pool
spec:
  weight: 70
  template:
    metadata:
      labels:
        workload: memory-intensive
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      taints:
        - key: dedicated
          value: memory
          effect: NoSchedule
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]   # databases need stable on-demand
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["r"]           # memory-optimized family (r5, r6i, r7i)
        - key: karpenter.k8s.aws/instance-memory
          operator: Gt
          values: ["16384"]       # at least 16 GiB RAM
  limits:
    cpu: 40
    memory: 500Gi
  disruption:
    consolidationPolicy: WhenEmpty    # only consolidate truly empty nodes
    consolidateAfter: 5m              # wait longer before removing
    expireAfter: 720h                 # rotate every 30 days (databases are sensitive)
```

---

### Pattern F: Graviton (arm64) pool for cost savings

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: graviton-pool
spec:
  weight: 90
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: graviton            # separate EC2NodeClass for arm64 AMI
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]       # Graviton/ARM instances only
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["m", "c", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["6"]           # only Graviton3+ (gen7, gen8)
  limits:
    cpu: 60
    memory: 250Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    expireAfter: 168h
```

For ARM64 pools, the EC2NodeClass must use an ARM-compatible AMI:

```yaml
amiSelectorTerms:
  - alias: "al2023@latest"   # AL2023 supports both amd64 and arm64 automatically
amiFamily: AL2023
```

---

### Pattern G: Stable pool (no disruption, for batch jobs)

```yaml
disruption:
  consolidationPolicy: WhenEmpty     # never consolidate underutilized nodes
  consolidateAfter: Never            # never auto-consolidate
  expireAfter: Never                 # never auto-expire
```

Use for long-running batch workloads where node churn would kill the job.

---

### Pattern H: Strict rotation pool (security compliance)

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 1m
  expireAfter: 24h    # rotate every node daily to pick up latest AMI patches
  budgets:
    - nodes: "1"      # only replace 1 node at a time
```

Combines frequent rotation with a budget to avoid rolling too many nodes at once.

---

## 5) Disruption Budget: Protecting Production

The `budgets` field limits how many nodes Karpenter can disrupt simultaneously. This prevents a consolidation run from draining half the cluster at once.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 30s
  expireAfter: 168h
  budgets:
    # Normal operation: max 20% of nodes at once
    - nodes: "20%"

    # Freeze all disruption during business hours (Monday–Friday 8am–6pm)
    - nodes: "0"
      schedule: "0 8 * * 1-5"   # starts at 8:00 AM Mon–Fri
      duration: 10h              # blocks for 10 hours (until 6:00 PM)
```

The schedule uses standard cron syntax (UTC). During the protected window, `nodes: "0"` means zero disruptions are allowed.

---

## 6) Pod-Level Integration

### Targeting a specific NodePool from a pod

Use `nodeSelector` to force a pod onto nodes from a specific pool (requires the pool to apply a matching label):

```yaml
# In the NodePool:
template:
  metadata:
    labels:
      pool-type: spot

# In the Pod/Deployment:
spec:
  nodeSelector:
    pool-type: spot
```

---

### Tolerating a dedicated pool taint

```yaml
# In the NodePool:
template:
  spec:
    taints:
      - key: dedicated
        value: gpu
        effect: NoSchedule

# In the Pod/Deployment:
spec:
  tolerations:
    - key: dedicated
      value: gpu
      effect: NoSchedule
```

Only pods with this toleration will be scheduled on GPU nodes.

---

### Requesting spot or on-demand from a pod

Pods can request a specific capacity type directly:

```yaml
spec:
  nodeSelector:
    karpenter.sh/capacity-type: spot    # or on-demand
```

Karpenter will ensure the pod lands on a node matching that capacity type.

---

## 7) Checking NodePool Status

```bash
# List all NodePools and their resource usage
kubectl get nodepools

# Describe a specific NodePool (shows current usage vs limits)
kubectl describe nodepool spot-pool

# List all nodes provisioned by Karpenter
kubectl get nodes -l karpenter.sh/nodepool

# See which NodePool each node belongs to
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type

# Watch Karpenter logs (provisioning decisions, consolidation actions)
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter
```
