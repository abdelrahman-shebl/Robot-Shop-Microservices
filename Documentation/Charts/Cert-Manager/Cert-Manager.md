# Cert-Manager

---

## 1) What Cert-Manager Does

Cert-manager automates the issuance and renewal of TLS certificates inside Kubernetes.

Without cert-manager:
- TLS certificates must be obtained manually (from Let's Encrypt or a CA),
- they must be uploaded as Kubernetes Secrets manually,
- they must be renewed manually before expiry.

With cert-manager:
- a `ClusterIssuer` or `Issuer` object defines the certificate authority and challenge method,
- a `Certificate` object declares what domain needs a certificate,
- cert-manager handles the ACME challenge, fetches the certificate, and stores it as a Kubernetes Secret,
- renewal is fully automatic before expiry.

```
Certificate CRD (domain: app.example.com)
        │
        ▼
  ClusterIssuer (Let's Encrypt via DNS-01)
        │
        ▼
  Route53 DNS record (_acme-challenge.app.example.com)
        │
        ▼
  Let's Encrypt validates and issues certificate
        │
        ▼
  Kubernetes Secret (TLS cert + key)
        │
        ▼
  Ingress / Traefik uses the secret for HTTPS
```

---

## 2) Challenge Types: HTTP-01 vs DNS-01

Cert-manager supports two ACME challenge types. The choice matters for how Let's Encrypt verifies domain ownership.

### HTTP-01

- Let's Encrypt sends a request to `http://<domain>/.well-known/acme-challenge/<token>`,
- requires port 80 to be publicly reachable,
- cannot issue wildcard certificates.

### DNS-01

- cert-manager creates a DNS TXT record `_acme-challenge.<domain>` in Route53,
- Let's Encrypt reads the DNS record to verify ownership,
- port 80 does not need to be open,
- supports wildcard certificates (`*.example.com`),
- works for internal clusters with no public HTTP access.

**This setup uses DNS-01 with Route53** — the safest and most flexible option for EKS clusters.

---

## 3) Chart Reference

| Field          | Value                                                          |
|----------------|----------------------------------------------------------------|
| Chart name     | `cert-manager`                                                 |
| Helm repo      | `https://charts.jetstack.io`                                   |
| ArtifactHub    | https://artifacthub.io/packages/helm/cert-manager/cert-manager |
| Version used   | `v1.17.1`                                                      |
| CRDs installed | `Certificate`, `ClusterIssuer`, `Issuer`, `CertificateRequest` |

---

## 4) How Cert-Manager Gets AWS Permissions

Cert-manager needs to write DNS TXT records to Route53 when performing DNS-01 challenges. This is done through EKS Pod Identity.

### The IAM permissions cert-manager needs

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["route53:GetChange"],
      "Resource": ["arn:aws:route53:::change/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZonesByName"],
      "Resource": ["*"]
    }
  ]
}
```

- `ChangeResourceRecordSets` — creates and deletes the `_acme-challenge` TXT record,
- `GetChange` — polls Route53 until the DNS change has propagated,
- `ListResourceRecordSets` / `ListHostedZonesByName` — discovers the correct hosted zone.

---

## 5) Setting Up the IAM Role: Old Way vs Module Way

### Old way (manual resources)

```bash
# 1. Create the IAM role
resource "aws_iam_role" "cert_manager_role" {
  name = "cert-manager-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

# 2. Create the policy
resource "aws_iam_policy" "cert_manager_policy" {
  name   = "cert-manager-policy"
  policy = file("${path.module}/iam-cert-manager.json")
}

# 3. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "cert_manager_attach" {
  role       = aws_iam_role.cert_manager_role.name
  policy_arn = aws_iam_policy.cert_manager_policy.arn
}

# 4. Bind the role to the cert-manager service account
resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = var.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager-sa"
  role_arn        = aws_iam_role.cert_manager_role.arn
}
```

---

### New way (Terraform module)

```bash
module "cert_manager_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "cert-manager"

  # Attaches the managed cert-manager Route53 policy automatically
  attach_cert_manager_policy = true

  # Scope access to only the hosted zone used by this cluster
  cert_manager_hosted_zone_arns = [module.zone.arn]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "cert-manager"
      service_account = "cert-manager-sa"
    }
  }

  depends_on = [module.eks]
}
```

| Old way                          | Module way                                           |
|----------------------------------|------------------------------------------------------|
| Write IAM trust policy manually  | Module generates it automatically                    |
| Write + attach policy separately | `attach_cert_manager_policy = true`                  |
| JSON policy file needed          | Policy is built into the module                      |
| 4 separate resources             | 1 module block                                       |
| Allows all zones by default      | `cert_manager_hosted_zone_arns` scopes to one zone   |

**To modify the permissions:**

- To allow all hosted zones: replace `cert_manager_hosted_zone_arns` with `["*"]`.
- To allow multiple zones: pass multiple ARNs in the list.
- To use a different service account name: change both `service_account` here and `serviceAccount.name` in the chart values.

---

## 6) Helm Values Walkthrough

Chart: `cert-manager` from `https://charts.jetstack.io`

```yaml
# Install the cert-manager CRDs (Certificate, ClusterIssuer, Issuer, etc.)
# Must be true on first install. Set to false only if CRDs are managed separately.
installCRDs: true

# Service account that receives the Pod Identity IAM role.
# Must match the name used in the pod identity association.
serviceAccount:
  create: true
  name: cert-manager-sa

# Tolerations allow cert-manager pods to run on the system node
# (tainted with workload-type=system:NoSchedule)
tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"

# The webhook validates Certificate and Issuer objects before they are saved.
# It also needs to run on the system node.
webhook:
  tolerations:
    - key: "workload-type"
      operator: "Equal"
      value: "system"
      effect: "NoSchedule"

# cainjector injects CA bundles into webhook configurations.
# It also needs to run on the system node.
cainjector:
  tolerations:
    - key: "workload-type"
      operator: "Equal"
      value: "system"
      effect: "NoSchedule"

# Resource limits for the main cert-manager controller
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

### How to adjust values from this base

**Change the service account name:**
```yaml
serviceAccount:
  name: my-cert-manager-sa
```
Then update the `service_account` in the pod identity module to match.

**Disable CRD installation (if managed separately):**
```yaml
installCRDs: false
```

**Remove system node restriction (if using regular nodes):**
```yaml
tolerations: []
webhook:
  tolerations: []
cainjector:
  tolerations: []
```

**Add resources for the webhook and cainjector too:**
```yaml
webhook:
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 64Mi

cainjector:
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

**Enable Prometheus metrics:**
```yaml
prometheus:
  enabled: true
  servicemonitor:
    enabled: true
```

---

## 7) ClusterIssuer Manifest

`ClusterIssuer` is a cluster-wide resource that defines how certificates are issued. It is deployed as a Kubernetes manifest (not part of the Helm chart), in the `K8s/cert-manager/` directory.

Two issuers are used: production and staging.

### Why two issuers?

Let's Encrypt production has strict rate limits (5 certificates per domain per week).
During testing or first setup, using the staging issuer prevents hitting those limits.
Staging certificates are not trusted by browsers but are functionally identical for testing.

### Production issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com          # Let's Encrypt sends renewal warnings here
    privateKeySecretRef:
      name: letsencrypt-dns-account-key  # stores the ACME account private key
    solvers:
      - dns01:
          route53:
            region: us-east-1
            # No credentials needed — Pod Identity handles AWS access
```

### Staging issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-dns-staging-account-key
    solvers:
      - dns01:
          route53:
            region: us-east-1
```

**To switch from staging to production:** change `issuerRef.name` in the `Certificate` objects from `letsencrypt-dns-staging` to `letsencrypt-dns`.

---

## 8) Certificate Manifest

Each service that needs HTTPS gets its own `Certificate` object. Cert-manager reads it and produces a Kubernetes `Secret` with the TLS cert and key.

### Standard certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-tls
  namespace: argocd          # must be in the same namespace as the Ingress using it
spec:
  secretName: argocd-tls    # the Secret that will hold the certificate
  issuerRef:
    name: letsencrypt-dns   # which ClusterIssuer to use
    kind: ClusterIssuer
  dnsNames:
    - argocd.example.com    # the domain this certificate covers
```

### How to adjust Certificate objects

**Use staging issuer (for testing):**
```yaml
  issuerRef:
    name: letsencrypt-dns-staging
    kind: ClusterIssuer
```

**Cover multiple subdomains:**
```yaml
  dnsNames:
    - app.example.com
    - api.example.com
```

**Issue a wildcard certificate:**
```yaml
  dnsNames:
    - "*.example.com"
```
Wildcards only work with DNS-01 challenge (HTTP-01 does not support them).

**Set custom renewal window:**
```yaml
  renewBefore: 360h    # renew 15 days before expiry (default is 30 days)
  duration: 2160h      # certificate lifetime: 90 days (Let's Encrypt default)
```

**Force immediate renewal (if cert is stuck):**
```bash
kubectl delete secret argocd-tls -n argocd
# cert-manager will immediately re-issue the certificate
```

---

## 9) How ArgoCD Deploys Cert-Manager

Two-application split:

**App 1 — `cert-manager` (wave `-5`):** installs the Helm chart and CRDs.

**App 2 — `cert-manager-manifests` (wave `-4`):** deploys `ClusterIssuer` and `Certificate` objects from `K8s/cert-manager/`.

`cert-manager` deploys at the earliest wave (`-5`) because it is a dependency for every other service that uses TLS. Without valid certificates, Traefik cannot serve HTTPS traffic and all ingress-based services fail.

`SkipDryRunOnMissingResource=true` is added to the manifests app because the `Certificate` and `ClusterIssuer` CRDs installed by app 1 may not be fully registered when app 2's dry-run phase starts.
