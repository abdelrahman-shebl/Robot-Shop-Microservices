# External Secrets Operator (ESO)

---

## 1) What ESO Does

External Secrets Operator syncs secrets from an external secret store (AWS Secrets Manager, SSM Parameter Store, Vault, etc.) into native Kubernetes `Secret` objects.

Without ESO:
- secrets are stored directly in Kubernetes (in Git or etcd),
- rotating a secret requires editing Kubernetes manifests and redeploying,
- secrets in Git are a security risk.

With ESO:
- secrets live in AWS Secrets Manager or SSM Parameter Store,
- ESO periodically pulls them and writes them into Kubernetes `Secret` objects,
- pods consume them as normal Kubernetes secrets,
- rotating a secret in AWS automatically propagates to the cluster.

```
AWS Secrets Manager / SSM
         │
         │  (ESO polls on schedule)
         ▼
  ExternalSecret CRD
         │
         ▼
  Kubernetes Secret  →  Pod env / volume
```

---

## 2) Chart Reference

| Field          | Value                                               |
|----------------|-----------------------------------------------------|
| Chart name     | `external-secrets`                                  |
| Helm repo      | `https://charts.external-secrets.io`                |
| ArtifactHub    | https://artifacthub.io/packages/helm/external-secrets/external-secrets |
| CRDs installed | `ExternalSecret`, `SecretStore`, `ClusterSecretStore` |

---

## 3) How ESO Gets AWS Permissions

ESO needs to call the AWS API to fetch secrets. This is done through **EKS Pod Identity** — the ESO pod is given an AWS IAM role without static credentials.

### The IAM permissions ESO needs

ESO requires read access to Secrets Manager and SSM:

```json
{
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds",
        "secretsmanager:ListSecrets",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Effect": "Allow",
      "Resource": ["*"]
    },
    {
      "Action": ["kms:Decrypt"],
      "Effect": "Allow",
      "Resource": ["*"]
    }
  ]
}
```

- `GetSecretValue` — read the actual secret content,
- `DescribeSecret` / `ListSecrets` — needed to discover and validate secrets,
- `ssm:GetParameter*` — read SSM Parameter Store values,
- `kms:Decrypt` — needed if secrets are encrypted with a KMS key.

---

## 4) Setting Up the IAM Role: Old Way vs Module Way

### Old way (manual role + policy + pod identity)

This approach creates every IAM resource explicitly.

```hcl
# 1. Create the IAM role
resource "aws_iam_role" "eso" {
  name = "eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
}

# 2. Create the IAM policy from a JSON file
resource "aws_iam_policy" "eso-policy" {
  name   = "eso-policy"
  policy = file("${path.module}/iam_eso.json")
}

# 3. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "eso-attach" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso-policy.arn
}

# 4. Bind the role to the ESO service account via Pod Identity
resource "aws_eks_pod_identity_association" "eso_pod_identity_association" {
  cluster_name    = var.cluster_name
  namespace       = "eso"
  service_account = "eso-sa"
  role_arn        = aws_iam_role.eso.arn
}
```

What each step does:
1. creates an IAM role with a trust policy that allows EKS Pod Identity to assume it,
2. creates the IAM policy with the secret-read permissions,
3. attaches the policy to the role,
4. binds the role to the `eso-sa` service account in the `eso` namespace.

---

### New way (Terraform module — fewer lines, same result)

The `eks-pod-identity` module wraps all four steps above into one block.

```hcl
module "external_secrets_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"
  name   = "external-secrets"

  # Attaches the managed ESO read policy automatically
  attach_external_secrets_policy = true

  # Scope the SSM access to only the parameters managed by this project
  external_secrets_ssm_parameter_arns = module.ssm.parameter_arns

  # Do not allow ESO to create new secrets in AWS (read-only)
  external_secrets_create_permission = false

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "eso"
      service_account = "eso-sa"
    }
  }

  depends_on = [module.eks]
}
```

Key differences from the old way:

| Old way                          | Module way                                         |
|----------------------------------|----------------------------------------------------|
| Write IAM trust policy manually  | Module generates it automatically                  |
| Write and attach policy manually | `attach_external_secrets_policy = true`            |
| JSON file for permissions        | Module has the policy built-in                     |
| 4 separate resources             | 1 module block                                     |
| Hard to scope per-parameter      | `external_secrets_ssm_parameter_arns` scopes ARNs  |

**To modify the permissions:**

- To restrict to specific SSM paths: set `external_secrets_ssm_parameter_arns` to a list of ARNs instead of `["*"]`.
- To allow Secrets Manager: uncomment `external_secrets_secrets_manager_arns = ["*"]` or pass specific ARNs.
- To allow KMS decryption on a specific key: set `external_secrets_kms_key_arns = ["arn:aws:kms:..."]`.
- To allow ESO to create secrets: set `external_secrets_create_permission = true`.

---

## 5) ESO Helm Values Walkthrough

Chart: `external-secrets` from `https://charts.external-secrets.io`

```yaml
# Install the ESO CRDs (ExternalSecret, SecretStore, ClusterSecretStore)
# Must be true on first install
installCRDs: true

# Service account that receives the Pod Identity IAM role
serviceAccount:
  create: true
  name: eso-sa    # must match the name used in the pod identity association
```

### How to adjust values from this base

**Change the service account name:**
```yaml
serviceAccount:
  name: my-custom-eso-sa
```
Then update the `service_account` field in the pod identity association to match.

**Disable CRD installation (if CRDs are managed separately):**
```yaml
installCRDs: false
```

**Add resource limits:**
```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

**Enable webhook (stricter validation):**
```yaml
webhook:
  create: true
```

**Enable certController (manages webhook certs):**
```yaml
certController:
  create: true
```

---

## 6) ESO Kubernetes Resources (The CRDs)

After the chart installs, two CRD objects control how secrets are fetched.

### `ClusterSecretStore` — connects to AWS

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-store
spec:
  provider:
    aws:
      service: SecretsManager   # or ParameterStore
      region: us-east-1
```

- `ClusterSecretStore` works across all namespaces (vs `SecretStore` which is namespace-scoped),
- `service: ParameterStore` to use SSM instead of Secrets Manager.

---

### `ExternalSecret` — pulls a secret into a namespace

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: robotshop
spec:
  refreshInterval: 1h            # how often ESO re-syncs from AWS
  secretStoreRef:
    name: aws-secrets-store
    kind: ClusterSecretStore
  target:
    name: db-credentials         # name of the resulting Kubernetes Secret
    creationPolicy: Owner
  data:
    - secretKey: username        # key inside the Kubernetes Secret
      remoteRef:
        key: /robotshop/db       # path in AWS Secrets Manager or SSM
        property: username       # field inside the secret JSON (optional)
    - secretKey: password
      remoteRef:
        key: /robotshop/db
        property: password
```

What this produces:
- a Kubernetes `Secret` named `db-credentials` in `robotshop` namespace,
- with keys `username` and `password` populated from AWS.

**To pull an entire secret object as-is:**
```yaml
  dataFrom:
    - extract:
        key: /robotshop/db       # pulls all keys from the AWS secret
```

---

## 7) How ArgoCD Deploys ESO

Two-application split (see ArgoCD-apps.md for the pattern):

**App 1 — `external-secrets-operator`:** installs the chart + CRDs (wave `-3`).

**App 2 — `external-secrets-manifests`:** deploys `ClusterSecretStore` and `ExternalSecret` objects from `K8s/eso/` (wave `-2`).

The `SkipDryRunOnMissingResource=true` sync option is added to app 2 to handle the window where CRDs may not be fully registered during the dry-run phase.
