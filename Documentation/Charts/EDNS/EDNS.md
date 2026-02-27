# External DNS (EDNS)

---

## 1) What External DNS Does

External DNS automatically manages DNS records in Route53 (or other DNS providers) based on Kubernetes `Ingress` and `Service` resources.

Without External DNS:
- every time a new service is deployed, a DNS record has to be created manually in Route53,
- changing a load balancer IP or hostname requires updating the DNS record manually.

With External DNS:
- the moment an `Ingress` or `Service` is created with a hostname, External DNS reads it,
- it creates the matching DNS record in Route53 automatically,
- when the resource is deleted, the DNS record is deleted too (if `policy: sync`).

```
Kubernetes Ingress / Service (with hostname)
              │
              │  (External DNS watches for changes)
              ▼
       Route53 Hosted Zone
              │
              ▼
     A / CNAME record pointing to
     the LoadBalancer or cluster IP
```

---

## 2) Chart Reference

| Field          | Value                                                       |
|----------------|-------------------------------------------------------------|
| Chart name     | `external-dns`                                              |
| Helm repo      | `https://kubernetes-sigs.github.io/external-dns/`           |
| ArtifactHub    | https://artifacthub.io/packages/helm/external-dns/external-dns |
| Version used   | `1.20.0`                                                    |

---

## 3) How External DNS Gets AWS Permissions

External DNS needs to call the Route53 API to create and delete records.

### The IAM permissions External DNS needs

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets"],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ],
      "Resource": ["*"]
    }
  ]
}
```

- `ChangeResourceRecordSets` — creates, updates, and deletes DNS records,
- `ListHostedZones` / `ListResourceRecordSets` — reads existing zones and records to avoid duplicates,
- `ListTagsForResources` — used to filter zones by tags.

---

## 4) Setting Up the IAM Role: Old Way vs Module Way

### Old way (manual role + policy + pod identity)

```hcl
# 1. Create the IAM role
resource "aws_iam_role" "edns_role" {
  name = "edns_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

# 2. Create the policy from a JSON file
resource "aws_iam_policy" "edns-policy" {
  name   = "edns-policy"
  policy = file("${path.module}/iam-EDNS.json")
}

# 3. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "edns-attach" {
  role       = aws_iam_role.edns_role.name
  policy_arn = aws_iam_policy.edns-policy.arn
}

# 4. Bind the role to the External DNS service account via Pod Identity
resource "aws_eks_pod_identity_association" "edns_pod_identity_association" {
  cluster_name    = var.cluster_name
  namespace       = "edns"
  service_account = "edns-sa"
  role_arn        = aws_iam_role.edns_role.arn
}
```

What each step does:
1. creates an IAM role with a trust policy for EKS Pod Identity,
2. creates the IAM policy with Route53 permissions,
3. attaches the policy to the role,
4. binds the role to the `edns-sa` service account in the `edns` namespace.

---

### New way (Terraform module)

```hcl
module "external_dns_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"
  name   = "external-dns"

  # Attaches the managed External DNS Route53 policy automatically
  attach_external_dns_policy = true

  # Scope access to only the hosted zone used by this cluster
  external_dns_hosted_zone_arns = [module.zone.arn]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "edns"
      service_account = "edns-sa"
    }
  }

  depends_on = [module.eks]
}
```

Key differences from the old way:

| Old way                          | Module way                                         |
|----------------------------------|----------------------------------------------------|
| Write IAM trust policy manually  | Module generates it automatically                  |
| Write IAM policy JSON file       | `attach_external_dns_policy = true`                |
| 4 separate resources             | 1 module block                                     |
| Allows all hosted zones          | `external_dns_hosted_zone_arns` scopes to one zone |

**To modify the permissions:**

- To allow all hosted zones: replace the list with `["*"]` or omit `external_dns_hosted_zone_arns`.
- To allow multiple zones: pass multiple ARNs in the list.
- To restrict to private zones only: set `zoneType: private` in the chart values and ensure the VPC is associated with the hosted zone.

---

## 5) External DNS Helm Values Walkthrough

Chart: `external-dns` from `https://kubernetes-sigs.github.io/external-dns/`

```yaml
# 1. The provider — which DNS service to manage
provider: aws

# 2. Domain filter — CRITICAL safety gate
# Only touch records that belong to these domains.
# Without this, External DNS could modify records in any hosted zone in the account.
domainFilters:
  - "example.com"

# 3. AWS region and zone type
aws:
  region: "us-east-1"
  zoneType: public    # public, private, or omit for both

# 4. Sync policy
# sync:        creates AND deletes records automatically (full automation)
# upsert-only: creates/updates but never deletes (safer during initial setup)
policy: sync

# 5. Ownership registry
# External DNS writes TXT records to mark which DNS records it owns.
# This prevents it from deleting records owned by another cluster or Terraform.
registry: txt
txtOwnerId: "my-cluster"       # unique name per cluster
txtPrefix: external-dns-       # prefix for the ownership TXT records

# 6. Service account — must match the pod identity association
serviceAccount:
  create: true
  name: "edns-sa"

# 7. Sources — what Kubernetes resources to watch
sources:
  - ingress    # watch Ingress objects (Traefik IngressRoute is covered separately)
  - service    # watch LoadBalancer-type Services
```

### How to adjust values from this base

**Change domain scope:**
```yaml
domainFilters:
  - "prod.example.com"
  - "staging.example.com"
```
External DNS will only create records under these domains and ignore everything else.

**Switch to upsert-only during initial setup:**
```yaml
policy: upsert-only
```
Safe to use when first deploying — prevents accidental deletion of existing records.
Switch back to `sync` once confident.

**Change ownership prefix (multiple clusters same zone):**
```yaml
txtOwnerId: "cluster-prod"
txtPrefix: "edns-prod-"
```
Each cluster needs a unique `txtOwnerId` so they do not delete each other's records.

**Watch only Ingress, not Services:**
```yaml
sources:
  - ingress
```

**Add resource limits:**
```yaml
resources:
  requests:
    cpu: 20m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

**Filter by annotation (only manage explicitly annotated resources):**
```yaml
annotationFilter: "external-dns.alpha.kubernetes.io/managed=true"
```
With this set, External DNS only creates records for Ingress/Service objects that have this annotation. Useful to avoid managing records for internal services.

---

## 6) Full Values Example with All Options

```yaml
provider: aws

domainFilters:
  - "example.com"

aws:
  region: "us-east-1"
  zoneType: public

policy: sync

registry: txt
txtOwnerId: "my-cluster"
txtPrefix: external-dns-

serviceAccount:
  create: true
  name: "edns-sa"

sources:
  - ingress
  - service

interval: 1m        # how often to reconcile (default: 1m)

resources:
  requests:
    cpu: 20m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

---

## 7) How It Works End to End

When a new Ingress is created in the cluster:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

External DNS:
1. detects the `host: myapp.example.com` annotation,
2. checks if it matches a domain in `domainFilters`,
3. looks up the current LoadBalancer hostname/IP for this Ingress,
4. creates an A or CNAME record in Route53 pointing `myapp.example.com` to that address,
5. creates a TXT record (`external-dns-myapp.example.com`) marking ownership.

When the Ingress is deleted (and `policy: sync`):
- both the A/CNAME and the ownership TXT record are removed from Route53.

---

## 8) How ArgoCD Deploys External DNS

From `argo-apps-values.tpl`:

```yaml
external-dns:
  namespace: argocd
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  sources:
    - chart: external-dns
      repoURL: https://kubernetes-sigs.github.io/external-dns/
      targetRevision: "1.20.0"
      helm:
        valueFiles:
          - $repo/terraform/modules/addons/values/edns-values.yaml
    - <<: *repo_link    # provides $repo alias pointing to the Git repo
  destination:
    namespace: edns
    server: https://kubernetes.default.svc
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-3"
```

- deploys at wave `-3` — early in the boot sequence, before application workloads need DNS,
- values file lives in the repo and is referenced via the `$repo` multi-source alias,
- `CreateNamespace=true` creates the `edns` namespace if it does not exist.
