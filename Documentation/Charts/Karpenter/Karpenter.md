# Karpenter

Companion file:
- [Karpenter-NodePool-NodeClass.md](Karpenter-NodePool-NodeClass.md)

---

## 1) What Karpenter Does

Karpenter is a Kubernetes node autoscaler. It watches for pods that cannot be scheduled (because no node has enough resources) and automatically provisions the right EC2 instance to run them — then terminates it when it is no longer needed.

### Why it replaces Cluster Autoscaler

The old approach (Cluster Autoscaler) works with pre-defined Auto Scaling Groups:
- you define fixed node groups with fixed instance types,
- the autoscaler only scales those groups up and down,
- if no group fits the pod's requirements, the pod stays pending.

Karpenter works differently:
- it reads the pod's resource requests and constraints directly,
- it picks the most cost-efficient EC2 instance type that satisfies those requirements,
- it provisions the node directly via the EC2 API (no ASG needed),
- it consolidates and removes underutilized nodes automatically.

```
Pod scheduled → no node available
         │
         ▼
  Karpenter reads pod requirements
  (CPU, memory, arch, zone, spot/on-demand)
         │
         ▼
  Karpenter selects cheapest matching EC2 instance
         │
         ▼
  EC2 instance launches and joins the cluster
         │
         ▼
  Pod is scheduled on new node
         │
  (later, when pod terminates)
         │
         ▼
  Karpenter detects idle node → terminates it
```

### Key capabilities

- **Just-in-time provisioning** — nodes appear in ~60 seconds, not minutes,
- **Cost optimization** — picks the cheapest instance type that fits the pod,
- **Spot-first with on-demand fallback** — maximizes savings, falls back automatically,
- **Consolidation** — moves workloads to fewer, fuller nodes and terminates the empty ones,
- **Node expiry** — rotates nodes on a schedule to pick up security patches,
- **Interruption handling** — reacts to Spot interruption notices via SQS before AWS reclaims the instance.

---

## 2) Required Pre-existing Infrastructure

Karpenter cannot work alone. Several AWS and Kubernetes resources must exist before Karpenter is deployed.

### Static System Node Group (EKS Managed Node Group)

Karpenter must NOT run on nodes it manages — this is the chicken-and-egg problem. If Karpenter runs on a node it controls, and that node is terminated for consolidation, Karpenter dies and can never recover.

The solution is a small, static Managed Node Group dedicated to system workloads. It is never managed by Karpenter.

```bash
eks_managed_node_groups = {
  karpenter_node_group = {
    instance_types = ["c7i-flex.large"]
    capacity_type  = "ON_DEMAND"   # never spot — must stay alive
    min_size       = 1
    max_size       = 2
    desired_size   = 1

    labels = { workload-type = "system" }
    taints = {
      system = {
        key    = "workload-type"
        value  = "system"
        effect = "NO_SCHEDULE"     # repels app pods from this node
      }
    }
  }
}
```

The taint `workload-type=system:NoSchedule` keeps application pods off the system node. Only pods with matching tolerations (ArgoCD, Karpenter, cert-manager, etc.) can land on it.

---

### Karpenter IAM Role + Pod Identity (karpenter_infra module)

Karpenter needs IAM permissions to call EC2 APIs (RunInstances, TerminateInstances, DescribeInstances, etc.) and to tag and manage nodes.

The `karpenter` submodule from the EKS module generates:
- the Karpenter controller IAM role with the required policy,
- the Pod Identity association so Karpenter's service account receives the role without static credentials,
- the Karpenter node IAM role (attached to every EC2 node Karpenter launches),
- optional SQS queue + EventBridge rules for Spot interruption handling.

```bash
module "karpenter_infra" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.15.1"

  cluster_name = var.cluster_name

  # Creates a Pod Identity association for Karpenter's service account
  create_pod_identity_association = true
  namespace       = "karpenter"
  service_account = "karpenter-sa"

  # Adds SSM access so nodes can be managed without SSH keys
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  depends_on = [module.eks]
}
```

Outputs used later:
- `module.karpenter_infra.queue_name` — SQS queue name for interruption handling,
- `module.karpenter_infra.node_iam_role_name` — the IAM role name assigned to Karpenter-launched nodes.

---

### SQS Queue + EventBridge Rules

When AWS is about to reclaim a Spot instance, it sends a 2-minute warning. Karpenter can receive this via an SQS queue and begin draining the node immediately — before the instance disappears.

The `karpenter_infra` module creates:
- an SQS queue for interruption events,
- EventBridge rules that route EC2 Spot interruption warnings, instance state changes, and scheduled maintenance events to the queue.

Without this, Karpenter only knows a node is gone after it is already terminated.

---

### Node Security Group Discovery Tag

Karpenter-launched nodes must join the cluster's security group. The EKS module is configured with a discovery tag:

```bash
node_security_group_tags = {
  "karpenter.sh/discovery" = var.cluster_name
}
```

Karpenter's EC2NodeClass reads this tag to find the correct security group when launching instances.

---

### Private Subnet Tags

Karpenter discovers which subnets to launch nodes into via tags:

```bash
private_subnet_tags = {
  "karpenter.sh/discovery" = var.cluster_name
}
```

Without this tag, Karpenter cannot find the subnets and will fail to launch nodes.

---

### Route53 Hosted Zone + VPC

Required for ingress-based services (Traefik, cert-manager, External DNS) that run on Karpenter nodes. Not a direct Karpenter dependency, but part of the overall infrastructure that Karpenter-managed nodes serve.

---

## 3) Deployment: Two Terraform Modules

Karpenter is split across two Terraform modules intentionally.

```
module "karpenter_infra"              →  IAM + SQS + Pod Identity
        (part of main EKS module setup)

module "karpenter_chart_and_crds"     →  Helm chart + CRDs + NodePool + EC2NodeClass
        (deployed after EKS exists)
```

```bash
module "karpenter_chart_and_crds" {
  source                 = "./modules/karpenter"
  queue_name             = module.karpenter_infra.queue_name
  cluster_name           = var.cluster_name
  karpenter_role         = module.karpenter_infra.node_iam_role_name
  private_subnet_ids     = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  depends_on             = [module.eks]
}
```

The second module (`karpenter_chart_and_crds`) installs:
1. the Karpenter Helm chart,
2. a `time_sleep` of 120s to wait for CRDs to register,
3. the `EC2NodeClass` manifest,
4. the `spot-pool` NodePool manifest,
5. the `ondemand-pool` NodePool manifest,
6. a destroy-time cleanup hook to drain nodes before Terraform removes the chart.

---

## 4) Chart Reference

| Field        | Value                                      |
|--------------|--------------------------------------------|
| Chart name   | `karpenter`                                |
| OCI registry | `oci://public.ecr.aws/karpenter`           |
| Version used | `1.8.1`                                    |
| CRDs         | `NodePool`, `EC2NodeClass`, `NodeClaim`     |

Note: Karpenter uses an OCI registry, not a traditional Helm repo. The `helm_release` source is the full OCI URI.

---

## 5) Helm Values Walkthrough

### Base values (`karpenter-values.tpl`)

```yaml
# Service account that receives the Pod Identity IAM role
serviceAccount:
  create: true
  name: "karpenter-sa"   # must match the name in karpenter_infra module

settings:
  # The EKS cluster Karpenter manages
  clusterName: ${cluster_name}    # injected by Terraform templatefile()

  # SQS queue for Spot interruption warnings
  # Karpenter polls this queue and begins node draining before the instance is reclaimed
  interruptionQueue: ${queue_name}   # injected by Terraform templatefile()

controller:
  resources:
    requests:
      cpu: "500m"
      memory: 1Gi
    limits:
      cpu: 1
      memory: 1Gi

  # CRITICAL: pin Karpenter to the static system node group
  # Karpenter must not run on nodes it manages
  nodeSelector:
    workload-type: "system"

# Toleration to run on the system node (which has this taint)
tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"
```

### What each field does

- `serviceAccount.name` — must match the `service_account` in the `karpenter_infra` module. Pod Identity injects the IAM role into this account.
- `settings.clusterName` — tells Karpenter which EKS cluster it is managing. Used when tagging EC2 instances and reading cluster auth.
- `settings.interruptionQueue` — the SQS queue name. Karpenter subscribes to it to receive Spot interruption events and react before termination.
- `controller.resources` — Karpenter is busy: it watches all pending pods, tracks all nodes, and interacts with EC2 APIs continuously. Giving it 1Gi memory and 500m CPU is appropriate for medium-sized clusters.
- `controller.nodeSelector` — forces the Karpenter pod onto the system node group. Without this, Karpenter could be scheduled on a node it provisioned and then gets killed when that node is consolidated.
- `tolerations` — allows Karpenter to land on the system node which carries the `workload-type=system:NoSchedule` taint.

### How to modify values

**Increase resources for large clusters (many nodes/pods):**
```yaml
controller:
  resources:
    requests:
      cpu: "1"
      memory: 2Gi
    limits:
      cpu: 2
      memory: 2Gi
```

**Enable Prometheus metrics:**
```yaml
controller:
  metrics:
    port: 8080

serviceMonitor:
  enabled: true
```

**Enable debug logging (troubleshooting):**
```yaml
controller:
  env:
    - name: LOGLEVEL
      value: debug
```

**Set a specific Karpenter log level:**
```yaml
logConfig:
  enabled: true
  logLevel:
    controller: debug
    webhook: error
```

**Batch provisioning window (reduces EC2 API calls during burst):**
```yaml
settings:
  batchMaxDuration: 10s     # wait up to 10s collecting pending pods before launching
  batchIdleDuration: 1s     # stop waiting if no new pods for 1s
```

---

## 6) CRD Wait and Destroy Cleanup

### CRD Wait

After the Helm chart is installed, Karpenter's CRDs (`NodePool`, `EC2NodeClass`) take time to register in the API server. Applying `NodePool` manifests before CRDs are ready causes the apply to fail.

A `time_sleep` resource of 120 seconds is added between the Helm install and the CRD resource applies:

```bash
resource "time_sleep" "wait_for_karpenter_crds" {
  create_duration = "120s"
  depends_on      = [helm_release.karpenter]
}
```

Both `kubectl_manifest.karpenter_node_class` and the NodePool resources depend on this sleep.

---

### Destroy Cleanup

When `terraform destroy` runs, Terraform removes resources in reverse dependency order. If the NodePool is deleted before nodes are drained, EC2 instances become orphaned and must be manually terminated.

A `terraform_data` resource with a `local-exec destroy` provisioner handles this:

```bash
resource "terraform_data" "karpenter_node_cleanup" {
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # 1. Delete the NodePool — Karpenter drains and terminates its nodes
      kubectl delete nodepool spot-pool --ignore-not-found=true --timeout=5m || true

      # 2. Failsafe: find any still-running EC2 instances tagged by Karpenter
      INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:karpenter.sh/nodepool,Values=spot-pool" \
                  "Name=instance-state-name,Values=running,pending" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text)

      # 3. Force terminate them if any remain
      if [ -n "$INSTANCE_IDS" ]; then
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
      fi
    EOT
  }
}
```

This runs before the NodePool manifest and Helm chart are removed, ensuring no orphaned EC2 instances remain after `terraform destroy`.

---

## 7) Infrastructure Summary

All components that need to exist before or alongside Karpenter:

| Component                  | Purpose                                                    | Where defined              |
|----------------------------|------------------------------------------------------------|----------------------------|
| EKS cluster                | The Kubernetes control plane                               | `module.eks`               |
| System Managed Node Group  | Static nodes for Karpenter + system pods                   | `module.eks` node groups   |
| VPC + private subnets      | Network for EC2 nodes, tagged for Karpenter discovery      | `module.vpc`               |
| Node security group tag    | Allows Karpenter-launched nodes to join the cluster SG     | `module.eks`               |
| Karpenter IAM role         | Permissions to call EC2, describe instances, tag resources | `module.karpenter_infra`   |
| Node IAM role              | Role attached to every EC2 node Karpenter launches         | `module.karpenter_infra`   |
| Pod Identity association   | Binds Karpenter's service account to its IAM role          | `module.karpenter_infra`   |
| SQS + EventBridge rules    | Spot interruption event delivery                           | `module.karpenter_infra`   |
| Helm chart                 | Karpenter controller deployment                            | `module.karpenter_chart_and_crds` |
| EC2NodeClass               | Defines AMI, subnets, SG, disk for launched nodes          | `module.karpenter_chart_and_crds` |
| NodePool (spot)            | Defines workload node requirements and limits              | `module.karpenter_chart_and_crds` |
| NodePool (on-demand)       | Fallback pool when spot is unavailable                     | `module.karpenter_chart_and_crds` |

---

## 8) Next File

For a deep reference on writing EC2NodeClass and NodePool objects — all fields, all options, and examples for different scenarios:

- [Karpenter-NodePool-NodeClass.md](Karpenter-NodePool-NodeClass.md)
