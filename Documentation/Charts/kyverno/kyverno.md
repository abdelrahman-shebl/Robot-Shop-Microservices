# Kyverno

Companion file: [Cosign-Sigstore.md](Cosign-Sigstore.md)

---

## 1) What Kyverno Is

Kyverno is a **policy engine for Kubernetes** that uses a Kubernetes-native approach: every policy is itself a Kubernetes resource (a CRD). There is no sidecar, no rego language, no separate policy server to manage.

Kyverno operates as an **admission controller** — it sits between `kubectl apply` (or any API call) and the Kubernetes API server. When a resource is created or updated, the API server forwards the request to Kyverno before writing it to etcd. Kyverno evaluates it against all applicable policies and either:
- **Allows** it (passes validation, applies any mutations),
- **Denies** it with an error message, or
- **Mutates** it silently (adds labels, sets defaults).

```
  kubectl apply / API call
         │
         ▼
  Kubernetes API Server
         │
         │  Admission Webhook (MutatingAdmissionWebhook + ValidatingAdmissionWebhook)
         ▼
  Kyverno
    ├── Mutate policies  → modify the resource before it is written
    ├── Validate policies → allow or deny
    └── Generate policies → create additional resources in response
         │
         ▼
  etcd (resource is written)
```

---

## 2) The Three Policy Modes

### Validate

Reject resource creation if it does not meet requirements. Can run in `Enforce` (hard block) or `Audit` (log only, never block) mode.

```yaml
spec:
  validationFailureAction: Enforce   # or Audit
```

Common uses: require labels, deny `latest` image tag, require resource limits, restrict registries.

### Mutate

Modify the incoming resource before writing it to etcd. The user never sees the mutation — the cluster silently applies it.

Common uses: add default labels, inject annotations, set default resource limits when not specified.

### Generate

Create new Kubernetes resources in response to other resource creation.

Common uses: auto-create a `NetworkPolicy` for every new namespace, copy a Secret into every namespace.

---

## 3) CRD Migration Hooks and ArgoCD

The Kyverno chart ships with CRD migration hooks — Jobs that run on install/upgrade to migrate data between CRD versions. These Jobs create `ClusterRole` and `ClusterRoleBinding` objects named `migrate-resources`. When ArgoCD tries to sync (or Kyverno upgrades), these resources already exist and the Jobs fail with `"already exists"` errors, breaking the sync.

**Fix applied in this project:**

```yaml
# kyverno-values.yaml
crds:
  migration:
    enabled: false   # disables the migrate-resources Job and its RBAC
```

This is safe because CRD migration only matters when upgrading between major Kyverno versions with breaking CRD schema changes. For fresh installs and minor upgrades it has no effect.

---

## 4) Tolerations for System Nodes

```yaml
global:
  tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"
```

Kyverno is cluster-critical infrastructure. It must run on the stable system node group (on-demand nodes, not spot). This toleration allows Kyverno pods to be scheduled onto nodes that have the `workload-type=system:NoSchedule` taint, which is applied to the system node group. Without this, Kyverno would land on spot nodes and could be interrupted during node replacement.

---

## 5) ImageValidatingPolicy

`ImageValidatingPolicy` is a Kyverno CRD specifically for **supply chain security** — it verifies that container images have been signed by a trusted party before a pod is allowed to run.

This is different from a standard `ClusterPolicy`. It uses Kyverno's built-in cosign integration to verify cryptographic signatures without any custom scripting.

### How it works

1. A pod creation or update request arrives at the API server.
2. The API server forwards it to Kyverno's admission webhook.
3. Kyverno's image verifier extracts all container image references from the pod spec.
4. For each image matching `matchImageReferences`, it contacts the OCI registry and/or Rekor transparency log to verify the signature.
5. If verification fails (image unsigned, wrong signer identity, wrong OIDC issuer) → pod is denied.

---

### The policy in this project

```yaml
# K8s/kyverno/kyverno.yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-robot-shop
spec:
  # ── Which resources to intercept ─────────────────────────────────────────
  matchConstraints:
    resourceRules:
      - apiGroups: [""]         # core API group (where Pod lives)
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
    # This is required. Without it Kyverno doesn't register the webhook
    # for Pod resources and the policy silently never runs.

  # ── Which images to verify ────────────────────────────────────────────────
  matchImageReferences:
    - glob: "docker.io/shebl22/rs-*"
    # Matches any image under the shebl22 Docker Hub account starting with 'rs-'
    # e.g., docker.io/shebl22/rs-cart, docker.io/shebl22/rs-catalogue, etc.
    # Images NOT matching this glob are ignored by this policy entirely.

  # ── Who is trusted to sign those images ──────────────────────────────────
  attestors:
    - name: github-actions
      cosign:
        keyless:       # keyless = no pre-distributed signing key; trust via OIDC identity
          identities:
            - subjectRegExp: "https://github.com/abdelrahman-shebl/Robot-Shop-Microservices/.github/workflows/CI-CD.yml@.*"
              # The OIDC subject that must have signed the image.
              # Must match the GitHub Actions workflow path that ran cosign.
              # The @.* allows any git ref (main, feature/*, etc.)
              
              issuer: "https://token.actions.githubusercontent.com"
              # The OIDC issuer. GitHub Actions always uses this URL.
              # This confirms the OIDC token came from GitHub, not some other provider.
```

### Why both `subjectRegExp` and `issuer` are required

The OIDC identity check has two parts:
- **issuer**: Who issued the OIDC token → must be GitHub (`token.actions.githubusercontent.com`)
- **subjectRegExp**: What workflow did the signing → must be the CI-CD.yml in this exact repo

Both must match. An attacker cannot satisfy both constraints:
- They cannot forge a token with `issuer=token.actions.githubusercontent.com` (they don't control GitHub's OIDC endpoint).
- Even if somehow they push an image and sign it with their own GitHub workflow, the `subjectRegExp` would not match their workflow path.

---

## 6) ImageValidatingPolicy: All Field Options

### matchImageReferences

Controls which images this policy applies to:

```yaml
matchImageReferences:
  # Option A: Glob matching (most common)
  - glob: "docker.io/myorg/rs-*"            # prefix match
  - glob: "ghcr.io/myorg/*"                 # entire org
  - glob: "*.azurecr.io/*"                  # any ACR registry
  - glob: "*"                                # ALL images everywhere

  # Option B: Explicit image name
  - name: "docker.io/myorg/rs-cart"
```

### Attestors: cosign keyless

```yaml
attestors:
  - name: my-ci
    cosign:
      keyless:
        identities:
          # Match exact workflow path at exact git ref
          - subject: "https://github.com/org/repo/.github/workflows/build.yml@refs/heads/main"
            issuer: "https://token.actions.githubusercontent.com"

          # Match any git ref of this workflow (main, branches, tags)
          - subjectRegExp: "https://github.com/org/repo/.github/workflows/build.yml@.*"
            issuer: "https://token.actions.githubusercontent.com"

          # Match any workflow in the repo (less specific)
          - subjectRegExp: "https://github.com/org/repo/.*"
            issuer: "https://token.actions.githubusercontent.com"

          # GitLab CI example
          - subjectRegExp: "https://gitlab.com/org/repo//.gitlab-ci.yml@.*"
            issuer: "https://gitlab.com"
```

### Attestors: cosign with a key pair (non-keyless)

For environments where OIDC is not available:

```yaml
attestors:
  - name: my-key
    cosign:
      key:
        # Reference to a Kubernetes secret containing the cosign public key
        secretRef:
          name: cosign-public-key
          namespace: kyverno
          key: cosign.pub
```

### validationFailureAction

```yaml
spec:
  validationFailureAction: Enforce   # hard block — pod will not start
  # validationFailureAction: Audit   # log only — pod starts but a PolicyReport is created
```

Use `Audit` first when rolling out a new policy. Switch to `Enforce` once you are confident all legitimate images are signed.

---

## 7) Other Kyverno Policy Types

### ClusterPolicy: Deny latest tag

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: deny-latest
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "Using 'latest' tag is not allowed. Pin to a specific version."
        pattern:
          spec:
            containers:
              - image: "!*:latest"    # deny any image ending in :latest
```

### ClusterPolicy: Require resource limits

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-limits
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaces: ["robot-shop"]
      validate:
        message: "CPU and memory limits are required."
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"      # must be set (any value)
                    memory: "?*"
```

### ClusterPolicy: Restrict registries

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-registries
spec:
  validationFailureAction: Enforce
  rules:
    - name: allow-only-approved-registries
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "Images must come from docker.io/shebl22 or public.ecr.aws."
        pattern:
          spec:
            containers:
              - image: "docker.io/shebl22/* | public.ecr.aws/*"
```

### ClusterPolicy: Mutate — add labels

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-managed-by-label
spec:
  rules:
    - name: add-label
      match:
        any:
          - resources:
              kinds: ["Deployment", "StatefulSet"]
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              managed-by: kyverno-injected   # added automatically if not present
```

### ClusterPolicy: Generate — auto NetworkPolicy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: default-deny-all
spec:
  rules:
    - name: create-default-deny
      match:
        any:
          - resources:
              kinds: ["Namespace"]
      generate:
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        name: default-deny-all
        namespace: "{{request.object.metadata.name}}"   # target: the new namespace
        synchronize: true   # keep in sync; if deleted, recreate
        data:
          spec:
            podSelector: {}   # match all pods
            policyTypes: ["Ingress", "Egress"]
            # no ingress or egress rules = deny all traffic
```

---

## 8) Verifying the Policy Works

```bash
# List all ImageValidatingPolicies
kubectl get imagevalidatingpolicies

# Describe the policy (shows current status and any errors)
kubectl describe imagevalidatingpolicy verify-robot-shop

# Try to create a pod with an unsigned image — should be denied
kubectl run test --image=docker.io/shebl22/rs-cart:unsigned-tag -n robot-shop

# Check PolicyReports (created in Audit mode with results of evaluations)
kubectl get policyreports --all-namespaces
kubectl get clusterpolicyreports

# View Kyverno admission controller logs
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50
```
