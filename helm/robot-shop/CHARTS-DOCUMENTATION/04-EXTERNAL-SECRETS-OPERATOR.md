# External Secrets Operator (ESO) - Complete Guide

## Overview

External Secrets Operator (ESO) bridges the gap between Kubernetes and external secret management systems (AWS Secrets Manager, HashiCorp Vault, etc.). It automatically fetches secrets from your secret vault and creates Kubernetes Secret objects, keeping them in sync.

**Why use ESO instead of manual secrets?**
- ✅ Secrets never stored in Git (security)
- ✅ Automatic rotation/sync with external source
- ✅ Single source of truth (AWS Secrets Manager, Vault, etc.)
- ✅ Different teams can manage secrets in their tool
- ✅ Audit trail in AWS CloudTrail
- ✅ Enables GitOps workflows (declare secrets as CRDs)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│         AWS Secrets Manager (Single Source of Truth)   │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Secret: db/mysql/password                          │ │
│  │ Value: "super-secret-password-123"                 │ │
│  │ Updated: Last modified 2 hours ago                 │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
         ↑
         │ ESO polls every 1 hour
         │
┌─────────────────────────────────────────────────────────┐
│         External Secrets Operator (ESO)                │
│  ┌────────────────────────────────────────────────────┐ │
│  │ SecretStore: AWS Secrets Manager credentials      │ │
│  │ ExternalSecret: Define which secrets to fetch     │ │
│  │ Actions:                                            │ │
│  │ 1. Connects to AWS Secrets Manager                │ │
│  │ 2. Fetches secret value                            │ │
│  │ 3. Creates/updates Kubernetes Secret              │ │
│  │ 4. Schedules next sync (1h from now)              │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────┐
│         Kubernetes Secret (Auto-created)               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ apiVersion: v1                                     │ │
│  │ kind: Secret                                       │ │
│  │ name: mysql-password                              │ │
│  │ type: Opaque                                       │ │
│  │ data:                                              │ │
│  │   password: "super-secret-password-123" (base64)  │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
│  ├─ Your applications mount this Secret               │
│  ├─ Pods access secrets via environment variables    │
│  └─ Secrets stay encrypted in etcd                   │
└─────────────────────────────────────────────────────────┘
```

---

## Helm Chart Configuration

### 1. **Basic ESO Installation**

```yaml
external-secrets-operator:
  enabled: true
  
  # Install Custom Resource Definitions (CRITICAL)
  installCRDs: true
  # ↓ Creates:
  #   - SecretStore CRD
  #   - ExternalSecret CRD
  #   - ClusterSecretStore CRD
  #   - ClusterExternalSecret CRD
  
  serviceAccount:
    create: true
    name: "eso-sa"
    # ↓ ESO pod needs this SA to access AWS
```

**Why installCRDs matters:**

```yaml
# Without installCRDs: true
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-secret
spec: ...
# ↑ Kubernetes rejects this: "ExternalSecret not found"

# With installCRDs: true
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret  ← CRD is installed, valid!
metadata:
  name: mysql-secret
spec: ...
```

---

### 2. **ServiceAccount for AWS Authentication**

```yaml
external-secrets-operator:
  serviceAccount:
    create: true
    name: "eso-sa"
    # annotations: {}  # Add annotations if using IRSA
```

---

## AWS Authentication: Two Approaches

### Approach 1: Traditional IRSA (IAM Roles for Service Accounts)

This approach uses temporary credentials rotated by AWS.

**Terraform configuration:**
```hcl
# 1. Create IAM Role
resource "aws_iam_role" "eso_role" {
  name = "eks-eso-role"

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
            "oidc.eks.REGION.amazonaws.com/id/EXAMPLEID:sub" = "system:serviceaccount:robot-shop:eso-sa"
            "oidc.eks.REGION.amazonaws.com/id/EXAMPLEID:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 2. Attach policy to read secrets
resource "aws_iam_role_policy" "eso_secrets_policy" {
  name = "eso-secrets-policy"
  role = aws_iam_role.eso_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:*"
      },
      # Optional: Allow reading from Parameter Store
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:ACCOUNT_ID:parameter/*"
      }
    ]
  })
}

# 3. Annotate ServiceAccount with role ARN
output "eso_role_arn" {
  value = aws_iam_role.eso_role.arn
}
```

**Apply to Kubernetes:**
```bash
kubectl patch serviceaccount eso-sa \
  -p '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::ACCOUNT_ID:role/eks-eso-role"}}}'
```

---

### Approach 2: Pod Identity (AWS EKS Pod Identity - Recommended!)

This is the newer, simpler approach. Pod Identity eliminates the complexity of OIDC.

**Terraform configuration:**
```hcl
# 1. Create IAM Role
resource "aws_iam_role" "eso_role" {
  name = "eks-eso-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# 2. Attach policy
resource "aws_iam_role_policy" "eso_policy" {
  name = "eso-secrets-policy"
  role = aws_iam_role.eso_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:*"
      }
    ]
  })
}

# 3. Create Pod Identity Association (THE MAGIC!)
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name           = aws_eks_cluster.main.name
  namespace              = "robot-shop"
  service_account        = "eso-sa"
  role_arn               = aws_iam_role.eso_role.arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso_role.arn
}
```

**Why Pod Identity is better:**

```
┌─────────────────────────┐
│   Approach 1: IRSA      │
├─────────────────────────┤
│ ✓ Works reliably       │
│ ✗ Complex setup        │
│ ✗ OIDC provider needed │
│ ✗ Troubleshooting hard │
│ Tokens rotate: 1 hour  │
└─────────────────────────┘

┌─────────────────────────┐
│  Approach 2: Pod ID     │
├─────────────────────────┤
│ ✓ Simple setup         │
│ ✓ No OIDC needed       │
│ ✓ AWS handles tokens   │
│ ✓ Easier debugging     │
│ Tokens rotate: 15 min  │
│ (Better security)      │
└─────────────────────────┘

Recommendation: Use Pod Identity for new clusters!
```

---

## Secret Management Manifests

### 1. **SecretStore CRD**

A SecretStore defines how to connect to AWS Secrets Manager.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secret-store
  namespace: robot-shop
  # ↓ Namespace-scoped: only pods in robot-shop can use this
spec:
  provider:
    aws:
      service: SecretsManager          # AWS service to use
      region: us-east-1                # AWS region
      auth:
        jwt:
          serviceAccountRef:
            name: eso-sa               # ServiceAccount with Pod Identity
            # ↓ With Pod Identity, this is all you need!
```

**Alternative: ClusterSecretStore (cluster-wide)**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-cluster-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-sa
            namespace: robot-shop
```

---

### 2. **ExternalSecret CRD**

An ExternalSecret declares which secret to fetch from AWS.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-credentials
  namespace: robot-shop
spec:
  # 1. Which SecretStore to use
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  
  # 2. How often to sync
  refreshInterval: 1h
  # ↓ Fetches and updates every 1 hour
  
  # 3. Name of the resulting Kubernetes Secret
  target:
    name: mysql-credentials-secret
    creationPolicy: Owner              # Create if doesn't exist
    template:
      engineVersion: v2
      data:
        username: "{{ .username }}"
        password: "{{ .password }}"
  
  # 4. Define which secrets to fetch
  data:
    # Fetch secret named "db/mysql/credentials" from AWS
    - secretKey: username
      remoteRef:
        key: db/mysql/credentials      # AWS secret name
        property: username             # JSON property
    
    - secretKey: password
      remoteRef:
        key: db/mysql/credentials
        property: password
```

**Flow:**
```
1. ExternalSecret object created
2. ESO controller detects it
3. Connects to AWS Secrets Manager
4. Fetches: db/mysql/credentials (JSON secret)
5. Extracts: { username: "user", password: "pass" }
6. Creates Kubernetes Secret:
   apiVersion: v1
   kind: Secret
   name: mysql-credentials-secret
   data:
     username: dXNlcg==        (base64)
     password: cGFzcw==        (base64)
7. Every 1 hour: Repeat steps 2-6
```

---

### 3. **Real-World Examples**

#### Example 1: MySQL Credentials
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mysql-secret
  namespace: robot-shop
spec:
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  
  refreshInterval: 1h
  
  target:
    name: mysql-password
    creationPolicy: Owner
  
  data:
    - secretKey: MYSQL_ROOT_PASSWORD
      remoteRef:
        key: db/mysql/root-password
        property: password
    
    - secretKey: MYSQL_USER
      remoteRef:
        key: db/mysql/exporter-user
        property: username
    
    - secretKey: MYSQL_PASSWORD
      remoteRef:
        key: db/mysql/exporter-user
        property: password
```

**Use in Kubernetes:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  template:
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-password      # ← Created by ExternalSecret
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql-password
              key: MYSQL_USER
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-password
              key: MYSQL_PASSWORD
```

---

#### Example 2: AWS API Keys for Application
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-aws-credentials
  namespace: robot-shop
spec:
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  
  refreshInterval: 6h
  
  target:
    name: app-aws-config
    creationPolicy: Owner
  
  data:
    - secretKey: AWS_ACCESS_KEY_ID
      remoteRef:
        key: app/aws/api-keys
        property: access_key_id
    
    - secretKey: AWS_SECRET_ACCESS_KEY
      remoteRef:
        key: app/aws/api-keys
        property: secret_access_key
```

---

#### Example 3: Database Connection String
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-db-connection
  namespace: robot-shop
spec:
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  
  refreshInterval: 2h
  
  target:
    name: payment-db-url
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # Construct full connection string from parts
        connection_string: "postgresql://{{ .db_user }}:{{ .db_password }}@{{ .db_host }}:5432/{{ .db_name }}"
  
  data:
    - secretKey: db_user
      remoteRef:
        key: db/payment/credentials
        property: username
    
    - secretKey: db_password
      remoteRef:
        key: db/payment/credentials
        property: password
    
    - secretKey: db_host
      remoteRef:
        key: db/payment/config
        property: hostname
    
    - secretKey: db_name
      remoteRef:
        key: db/payment/config
        property: database
```

**Use in application:**
```yaml
env:
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: payment-db-url
      key: connection_string
```

---

## AWS Secrets Manager Structure

Best practices for organizing secrets:

```
SecretsManager hierarchy:
├─ db/
│  ├─ mysql/
│  │  ├─ root-password          → { password: "..." }
│  │  ├─ exporter-user          → { username: "...", password: "..." }
│  │  └─ credentials            → { username: "...", password: "..." }
│  ├─ mongodb/
│  │  └─ uri                    → { uri: "mongodb://..." }
│  └─ postgres/
│     └─ credentials            → { username: "...", password: "..." }
├─ app/
│  ├─ aws/
│  │  └─ api-keys               → { access_key_id: "...", secret_access_key: "..." }
│  └─ payment/
│     └─ stripe-key             → { publishable_key: "...", secret_key: "..." }
└─ certificates/
   └─ tls/
      └─ app-cert               → { cert: "...", key: "..." }
```

**Create in AWS:**
```bash
# MySQL root password
aws secretsmanager create-secret \
  --name db/mysql/root-password \
  --secret-string '{"password":"super-secret-123"}'

# MongoDB URI
aws secretsmanager create-secret \
  --name db/mongodb/uri \
  --secret-string '{"uri":"mongodb://user:pass@host:27017"}'
```

---

## IAM Policy Examples

### Minimal Policy (Read-Only)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:*"
    }
  ]
}
```

### Restricted Policy (Specific Secrets Only)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:db/*",
        "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:app/aws/*"
      ]
    }
  ]
}
```

### With Parameter Store Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:*:ACCOUNT_ID:parameter/*"
    }
  ]
}
```



---

## Manifest Files in Your ESO Directory

Your charts/eso/ folder contains these files:

### 1. **SecretStore.yaml**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-store
  namespace: robot-shop
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: eso-sa
```

### 2. **db-external-secret.yaml**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: robot-shop
spec:
  secretStoreRef:
    name: aws-secrets-store
    kind: SecretStore
  
  refreshInterval: 1h
  
  target:
    name: db-credentials-secret
    creationPolicy: Owner
  
  data:
    - secretKey: mysql-root-password
      remoteRef:
        key: db/mysql/root-password
        property: password
    
    - secretKey: mongodb-uri
      remoteRef:
        key: db/mongodb/connection
        property: uri
```

### 3. **ESO-IAM.tf** & **iam_eso.json**

Terraform configuration and policy for ESO IAM role.

```hcl
# ESO-IAM.tf structure
resource "aws_iam_role" "eso_role" {
  name = "eks-eso-role"
  assume_role_policy = jsonencode(...)
}

resource "aws_iam_role_policy" "eso_secrets" {
  name = "eso-secrets-policy"
  role = aws_iam_role.eso_role.id
  policy = file("${path.module}/iam_eso.json")
}

# iam_eso.json content
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:*"
    }
  ]
}
```

---

## Pod Identity Setup (Easiest Method!)

```hcl
# Add to your Terraform

# 1. Create IAM role for ESO
resource "aws_iam_role" "eso_pod_identity" {
  name = "eks-eso-pod-identity"

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

# 2. Attach secrets policy
resource "aws_iam_role_policy_attachment" "eso_secrets_policy" {
  role       = aws_iam_role.eso_pod_identity.name
  policy_arn = aws_iam_policy.eso_secrets_policy.arn
}

resource "aws_iam_policy" "eso_secrets_policy" {
  name = "eso-secrets-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:*:ACCOUNT_ID:secret:*"
    }]
  })
}

# 3. Create Pod Identity association
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name           = aws_eks_cluster.main.name
  namespace              = "robot-shop"
  service_account        = "eso-sa"
  role_arn               = aws_iam_role.eso_pod_identity.arn
}
```

**That's it! No OIDC provider configuration needed!**

---

## Troubleshooting

### Problem: "Unable to assume role"
```bash
# Check Pod Identity association
kubectl describe sa eso-sa -n robot-shop

# Should show annotation:
# eks.amazonaws.com/pod-identity-association: arn:aws:...
```

### Problem: "Failed to get secret from AWS"
```bash
# Check ESO logs
kubectl logs -l app.kubernetes.io/name=external-secrets -n robot-shop

# Verify AWS credentials in Pod:
kubectl exec -it <eso-pod> -- env | grep AWS

# Test AWS CLI
kubectl exec -it <eso-pod> -- aws secretsmanager get-secret-value \
  --secret-id db/mysql/root-password --region us-east-1
```

### Problem: "SecretStore not found"
```yaml
# Ensure SecretStore is in same namespace as ExternalSecret
kubectl get secretstore -n robot-shop

# Or use ClusterSecretStore (cluster-wide):
kind: ClusterSecretStore  # Instead of SecretStore
```

---

## Production Checklist

- [ ] Create IAM role for ESO (use Pod Identity)
- [ ] Create AWS Secrets Manager secrets in structured format
- [ ] Deploy SecretStore/ClusterSecretStore
- [ ] Create ExternalSecrets for all sensitive data
- [ ] Test secret sync: `kubectl get secret mysql-password -o yaml`
- [ ] Verify refresh interval works (check timestamps)
- [ ] Monitor ESO logs for errors
- [ ] Backup AWS Secrets Manager values
- [ ] Document secret naming convention for team
- [ ] Set up alerts for ExternalSecret failures

---

## Reference

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [Terraform AWS Modules - ESO](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/external_secrets_operator)
- [AWS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [ExternalSecret CRD](https://external-secrets.io/latest/api/externalsecret/)
