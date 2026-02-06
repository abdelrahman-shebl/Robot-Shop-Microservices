# External DNS - Complete Guide

## Overview

ExternalDNS automatically manages DNS records in AWS Route53 (or other providers) based on your Kubernetes Ingress and Service resources. Instead of manually creating Route53 records, ExternalDNS watches your cluster and updates DNS automatically.

**The problem it solves:**
```
Traditional workflow (Manual):
1. Create Ingress in Kubernetes
2. Manually log into AWS Route53 console
3. Create A record pointing to Traefik IP
4. Delete record when ingress removed
5. Update when IP changes
6. ❌ Error-prone, repetitive, slow

ExternalDNS workflow (Automated):
1. Create Ingress in Kubernetes
2. ExternalDNS detects it
3. ExternalDNS creates Route53 record automatically
4. Delete ingress → record deleted
5. IP changes → record updated automatically
6. ✅ Fast, reliable, GitOps-friendly
```

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│        Kubernetes Cluster                      │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  Ingress: prometheus.yourdomain.com      │  │
│  │  Service: grafana.yourdomain.com         │  │
│  │  Service: opencost.yourdomain.com        │  │
│  └──────────────────────────────────────────┘  │
│            ↑                                    │
│            │ Watches for changes               │
│  ┌──────────────────────────────────────────┐  │
│  │  ExternalDNS Pod                         │  │
│  │  - Every 30s checks Ingress/Service      │  │
│  │  - Extracts host names                  │  │
│  │  - Compares with Route53                │  │
│  │  - Creates/updates/deletes DNS records  │  │
│  └──────────────────────────────────────────┘  │
│            ↓ AWS API calls                      │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│    AWS Route53 (DNS Service)                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  Zone: yourdomain.com                         │
│  ┌──────────────────────────────────────────┐  │
│  │ prometheus  A  1.2.3.4  (auto-created)   │  │
│  │ grafana     A  1.2.3.4  (auto-created)   │  │
│  │ opencost    A  1.2.3.4  (auto-created)   │  │
│  │                                          │  │
│  │ (ExternalDNS manages these!)             │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Helm Chart Configuration

### 1. **Provider Configuration**

```yaml
external-dns:
  enabled: true
  
  # Tell ExternalDNS which cloud provider to use
  provider: aws
  # Other options: azure, gcp, digitalocean, route53 (explicit), etc.
```

---

### 2. **Domain Filtering (CRITICAL Safety Feature)**

```yaml
external-dns:
  domainFilters:
    - shebl.com  # The domain you manage with ExternalDNS
    # Can add multiple:
    # - shebl.com
    # - app.shebl.com
    # - api.shebl.com
```

**Why domain filters matter:**

```yaml
# WITHOUT domainFilter (DANGEROUS):
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
  - host: app.yourdomain.com
    # ExternalDNS: "I'll create this DNS record"
    # PROBLEM: yourdomain.com might contain 10,000 records!
    # ExternalDNS could delete them by mistake!

# WITH domainFilter: shebl.com (SAFE):
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
spec:
  rules:
  - host: prometheus.shebl.com
    # ExternalDNS: "prometheus.shebl.com matches my filter"
    # "I'll safely create it"
    
  - host: other.differentdomain.com
    # ExternalDNS: "other.differentdomain.com not in my filter"
    # "I'll ignore this"
```

---

### 3. **AWS Configuration**

```yaml
external-dns:
  provider: aws
  
  aws:
    region: us-east-1          # AWS region where Route53 is
    zoneType: public            # public, private, or restricted
    # Options explained:
    # - public: Create public Route53 hosted zones
    # - private: Create private Route53 zones (VPC-only)
    # - restricted: Both public and private
```

---

### 4. **Synchronization Policy**

```yaml
external-dns:
  policy: sync
  # Two options:
  # - sync: Create AND Delete records (full automation)
  # - upsert-only: Create/Update but NEVER delete (safer for beginners)
```

**Policy comparison:**

```yaml
# policy: sync (Full automation)
Route53 Records (before):
  prometheus  A  1.2.3.4
  grafana     A  1.2.3.4
  old-app     A  5.6.7.8  ← Orphaned record

Kubernetes (truth):
  Ingress: prometheus, grafana

ExternalDNS action:
  ✓ Create/update prometheus
  ✓ Create/update grafana
  ✗ DELETE old-app (no matching Ingress)
  
Result: DNS stays perfectly in sync

# policy: upsert-only (Conservative)
Route53 Records (before):
  prometheus  A  1.2.3.4
  grafana     A  1.2.3.4
  old-app     A  5.6.7.8  ← Kept safely

Kubernetes (truth):
  Ingress: prometheus, grafana

ExternalDNS action:
  ✓ Create/update prometheus
  ✓ Create/update grafana
  ✗ SKIP old-app (doesn't delete anything)
  
Result: DNS stays up-to-date, nothing deleted
```

**When to use each:**

```yaml
# Production cluster (trust ExternalDNS):
policy: sync
# Pro: Clean DNS records, no manual cleanup
# Con: Could delete records if filter is wrong

# Development/Learning:
policy: upsert-only
# Pro: Safe, never deletes
# Con: Orphaned records accumulate
```

---

### 5. **Registry & Ownership (TXT Records)**

```yaml
external-dns:
  registry: txt                    # Use TXT records for ownership
  txtOwnerId: my-eks-cluster-id    # Unique cluster identifier
  txtPrefix: external-dns-          # Prefix for TXT records
```

**How registry works:**

```
Without registry (DANGEROUS with policy: sync):
┌──────────────────────────────────────┐
│ Route53 Records                      │
│ prometheus  A  1.2.3.4               │
│ grafana     A  1.2.3.4               │
│                                      │
│ Team member's script creates:        │
│ prometheus  A  9.9.9.9  (overwrites!)│
│                                      │
│ ExternalDNS sees:                    │
│ "prometheus record exists, not mine" │
│ (Unsure if it owns it)               │
│ "I'll delete it" (DISASTER!)         │
└──────────────────────────────────────┘

With registry: txt (SAFE):
┌──────────────────────────────────────┐
│ Route53 Records                      │
│ prometheus  A  1.2.3.4               │
│ external-dns-my-cluster-id TXT ...   │
│   (Proves ExternalDNS owns this)     │
│                                      │
│ Team member's script creates:        │
│ prometheus  A  9.9.9.9               │
│ (No TXT record = not owned by us)    │
│                                      │
│ ExternalDNS sees:                    │
│ "TXT record proves I own this"       │
│ "Safe to manage"                     │
│ Updates to 1.2.3.4 (CORRECT!)        │
└──────────────────────────────────────┘
```

**Why TXT records matter:**

1. **Safety**: Prevents cross-cluster conflicts
2. **Audit**: Shows which cluster owns which record
3. **Debugging**: Can search for `external-dns-` to find all managed records

---

### 6. **ServiceAccount (For AWS Authentication)**

```yaml
external-dns:
  serviceAccount:
    create: true
    name: "edns-sa"
    # annotations: {}  # Add annotations if using IRSA
```

---

### 7. **What to Watch (Sources)**

```yaml
external-dns:
  sources:
    - ingress    # Watch Ingress resources
    - service    # Watch Service resources
```

**What each source does:**

```yaml
# sources: [ingress, service]

# 1. Ingress source watches:
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
spec:
  rules:
  - host: prometheus.shebl.com
    # ↑ ExternalDNS creates Route53 record for this

# 2. Service source watches:
apiVersion: v1
kind: Service
metadata:
  name: api
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.shebl.com
spec:
  type: LoadBalancer
  # ↑ ExternalDNS creates Route53 record for api.shebl.com
```

---

## AWS Setup: Required IAM Policy

ExternalDNS needs permissions to create/read/delete Route53 records.

### IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    }
  ]
}
```

**Explanation:**

```
- route53:ChangeResourceRecordSets
  → Create, update, delete DNS records
  
- route53:ListHostedZones
  → List all Route53 hosted zones
  
- route53:ListResourceRecordSets
  → See current DNS records (for sync)
  
- route53:ListHostedZonesByName
  → Find zones by name (for efficiency)
```

### Terraform Configuration

#### Option 1: Using IRSA (IAM Roles for Service Accounts)

```hcl
# Create IAM Role
resource "aws_iam_role" "edns_role" {
  name = "eks-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/EXAMPLEID"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.eks.REGION.amazonaws.com/id/EXAMPLEID:sub" = "system:serviceaccount:robot-shop:edns-sa"
          }
        }
      }
    ]
  })
}

# Attach Route53 policy
resource "aws_iam_role_policy" "edns_route53" {
  name = "edns-route53-policy"
  role = aws_iam_role.edns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })
}

# Annotate ServiceAccount
resource "kubernetes_service_account_v1" "edns_sa" {
  metadata {
    name      = "edns-sa"
    namespace = "robot-shop"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.edns_role.arn
    }
  }
}
```

#### Option 2: Using Pod Identity (Simpler!)

```hcl
# Create IAM Role
resource "aws_iam_role" "edns_pod_identity" {
  name = "eks-external-dns-pod-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach policy
resource "aws_iam_role_policy_attachment" "edns_route53" {
  role       = aws_iam_role.edns_pod_identity.name
  policy_arn = aws_iam_policy.edns_route53.arn
}

resource "aws_iam_policy" "edns_route53" {
  name = "edns-route53-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListHostedZonesByName"
      ]
      Resource = "*"
    }]
  })
}

# Create Pod Identity Association
resource "aws_eks_pod_identity_association" "edns" {
  cluster_name           = aws_eks_cluster.main.name
  namespace              = "robot-shop"
  service_account        = "edns-sa"
  role_arn               = aws_iam_role.edns_pod_identity.arn
}
```



---

## DNS Setup: What ExternalDNS Manages

### Ingress Example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-dns
  namespace: robot-shop
spec:
  ingressClassName: traefik
  rules:
  - host: prometheus.shebl.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-service
            port:
              number: 80
```

**ExternalDNS action:**
```
Detected: Ingress with host: prometheus.shebl.com
Checks domainFilters: Is "prometheus.shebl.com" under "shebl.com"? YES ✓
Gets Traefik IP: 1.2.3.4
Route53 action: Creates/updates record
  prometheus.shebl.com  A  1.2.3.4

Result: Access via https://prometheus.shebl.com (automatic!)
```

---

### Service Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: robot-shop
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.shebl.com
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
```

**ExternalDNS action:**
```
Detected: Service with hostname annotation: api.shebl.com
Gets LoadBalancer IP: 2.3.4.5
Route53 action: Creates record
  api.shebl.com  A  2.3.4.5
```

---

## Complete ExternalDNS Configuration Example

```yaml
external-dns:
  enabled: true

  # 1. Cloud Provider
  provider: aws

  # 2. Domain Safety Filter
  domainFilters:
    - shebl.com
    # Add subdomains if needed:
    # - app.shebl.com
    # - api.shebl.com

  # 3. AWS Configuration
  aws:
    region: us-east-1
    zoneType: public

  # 4. Sync Policy
  policy: sync
  # Start with upsert-only if learning:
  # policy: upsert-only

  # 5. TXT Registry (Safety)
  registry: txt
  txtOwnerId: my-eks-cluster-id
  txtPrefix: external-dns-

  # 6. ServiceAccount
  serviceAccount:
    create: true
    name: "edns-sa"
    # annotations:
    #   eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/eks-external-dns-role"

  # 7. What to Watch
  sources:
    - ingress
    - service

  # 8. Resources
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

  # 9. Logging
  logLevel: info  # Change to debug for troubleshooting
```

---

## Troubleshooting

### Problem: "Unable to assume role"

```bash
# Check Pod Identity association
kubectl describe sa edns-sa -n robot-shop

# Should show:
# eks.amazonaws.com/pod-identity-association: arn:aws:eks:...
```

### Problem: DNS records not created

```bash
# Check ExternalDNS logs
kubectl logs -l app.kubernetes.io/name=external-dns -n robot-shop

# Common errors:
# 1. "No hosted zone found for ..."
#    → Domain filter doesn't match hosted zone
# 2. "AccessDenied: User is not authorized to perform: route53:..."
#    → IAM policy missing permissions
# 3. "Record already exists"
#    → Another tool is managing the record
```

### Problem: Records deleted unexpectedly

```bash
# Check ExternalDNS sync policy
kubectl get deployment external-dns -o yaml | grep policy

# If policy: sync, check what triggered deletion:
kubectl logs external-dns --tail=50 | grep "Delete"
```

---

## Best Practices

### 1. Start Conservative

```yaml
# Week 1: Learn how it works
policy: upsert-only   # Never deletes

# Week 2: After verification
policy: sync          # Full automation
```

### 2. Use Domain Filters Strictly

```yaml
# Good (restrictive):
domainFilters:
  - shebl.com

# Bad (too broad):
domainFilters: []     # Watches ALL domains!
```

### 3. Always Use Registry

```yaml
registry: txt
txtOwnerId: <unique-cluster-id>
# Prevents cross-cluster conflicts
```

### 4. Document Your Setup

```bash
# Create a reference
echo "ExternalDNS Cluster ID: my-eks-cluster-prod"
echo "Domain: shebl.com"
echo "Policy: sync"
echo "Sources: ingress, service"
```

---

## Production Checklist

- [ ] IAM role created with Route53 permissions
- [ ] Pod Identity association established
- [ ] Domain filters configured correctly
- [ ] TXT registry enabled for safety
- [ ] Policy set to sync (or upsert-only for learning)
- [ ] ServiceAccount created in correct namespace
- [ ] Helm values match your setup
- [ ] Test with single Ingress first
- [ ] Verify DNS record created in Route53
- [ ] Monitor logs for errors
- [ ] Set up alerting for sync failures

---

## Reference

- [ExternalDNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [ExternalDNS on AWS](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
- [Route53 API Reference](https://docs.aws.amazon.com/Route53/latest/APIReference/)
