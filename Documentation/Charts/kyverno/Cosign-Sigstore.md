# Cosign, Sigstore, and Image Signing

Companion file: [kyverno.md](kyverno.md)

---

## 1) The Problem: You Cannot Trust an Image Tag

A Docker image tag (`rs-cart:abc123sha`) is a mutable pointer. Anyone with push access to the registry can overwrite it at any time with a different image. Your pipeline built and tested image A, but by the time Kubernetes pulls it, it might be image B.

This is called a **supply chain attack** — malicious code is injected between when an image is built and when it runs. Famous examples: SolarWinds, the XZ Utils backdoor, `event-stream` npm package. Kubernetes has no native mechanism to verify that what it is pulling is what your CI/CD built.

**The solution:** cryptographic image signing. The CI/CD pipeline signs the image after building it. Kubernetes (via Kyverno) verifies the signature before running any pod. An image without a valid signature from the authorized CI workflow is refused.

---

## 2) The Sigstore Ecosystem

Sigstore is an open-source project (backed by Google, Red Hat, and Purdue University) that provides free, transparent, auditable infrastructure for software signing. It consists of four components:

```
  ┌─────────────────────────────────────────────────────────────────┐
  │  SIGSTORE ECOSYSTEM                                             │
  │                                                                 │
  │  cosign ──────── the CLI tool for signing and verifying images  │
  │                                                                 │
  │  Fulcio ──────── a Certificate Authority that issues short-lived│
  │                  signing certificates tied to OIDC identities   │
  │                                                                 │
  │  Rekor ───────── an append-only transparency log that records   │
  │                  every signing event publicly and permanently   │
  │                                                                 │
  │  ctlog ───────── a certificate transparency log (used internally│
  │                  by Fulcio; rarely interacted with directly)    │
  └─────────────────────────────────────────────────────────────────┘
```

These services are hosted publicly at:
- Fulcio: `https://fulcio.sigstore.dev`
- Rekor: `https://rekor.sigstore.dev`

---

## 3) OIDC: The Identity Foundation

**OIDC (OpenID Connect)** is a standard identity protocol built on top of OAuth 2.0. It allows a system (like GitHub Actions) to prove *who* is performing an action by issuing a signed JWT (JSON Web Token) containing identity claims.

### What a GitHub Actions OIDC token contains

When a GitHub Actions workflow runs with `permissions: id-token: write`, GitHub's OIDC provider issues a JWT for that specific workflow run. The token contains:

```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:org/repo:ref:refs/heads/main:workflow:.github/workflows/CI-CD.yml",
  "aud": "sigstore",
  "job_workflow_ref": "org/repo/.github/workflows/CI-CD.yml@refs/heads/main",
  "repository": "org/repo",
  "ref": "refs/heads/main",
  "sha": "abc123...",
  "run_id": "1234567890",
  "exp": 1234567890
}
```

Key fields:
- **`iss` (issuer)**: Who created this token — always `https://token.actions.githubusercontent.com` for GitHub
- **`sub` (subject)**: The exact identity — which repo, branch, and workflow file
- **`exp` (expiry)**: This token expires in ~10 minutes. It is single-use, bound to one workflow run.

This token cannot be forged. You cannot create a token claiming to be from GitHub's OIDC endpoint unless you control GitHub's private signing key. Nobody does.

---

## 4) Keyless Signing: The Full Flow

"Keyless" means there is no long-lived private key to manage, rotate, or leak. Identity replaces keys. Here is exactly what happens when `cosign sign` runs in the pipeline:

```
  GitHub Actions runner
  (workflow: CI-CD.yml, branch: main)
         │
         │  1. Request OIDC token from GitHub's OIDC provider
         │     Requires: permissions.id-token: write in workflow
         ▼
  GitHub OIDC Provider
  (https://token.actions.githubusercontent.com)
         │
         │  Issues short-lived JWT (expires ~10 min)
         │  sub = "...CI-CD.yml@refs/heads/main"
         ▼
  cosign (running on the runner)
         │
         │  2. Generate ephemeral key pair (only lives in memory, never saved)
         │
         │  3. Present OIDC token to Fulcio Certificate Authority
         ▼
  Fulcio (https://fulcio.sigstore.dev)
         │
         │  4. Validates the OIDC token with GitHub's JWKS endpoint
         │  5. Issues a short-lived X.509 signing certificate (expires 10 min)
         │     The certificate embeds the identity from the token:
         │       SubjectAltName = "https://github.com/org/repo/.github/workflows/CI-CD.yml@refs/heads/main"
         │       OIDC Issuer Extension = "https://token.actions.githubusercontent.com"
         ▼
  cosign
         │
         │  6. Sign the image digest using the ephemeral private key
         │     Signs: sha256:abc123... (the immutable image digest)
         │
         │  7. Upload signature + certificate to Rekor transparency log
         ▼
  Rekor (https://rekor.sigstore.dev)
         │
         │  8. Appends an immutable entry to its log:
         │     {
         │       "signature": "<base64 sig>",
         │       "certificate": "<cert with workflow identity>",
         │       "imageDigest": "sha256:abc123...",
         │       "timestamp": "2026-02-23T10:00:00Z",
         │       "logIndex": 123456789
         │     }
         │  9. Returns a "signed entry timestamp" (SET) proving this was logged
         ▼
  cosign
         │
         │  10. Attaches the signature to the OCI image in the registry
         │      as an OCI artifact (stored alongside the image, not inside it)
         │      The ephemeral private key is discarded — it is never stored anywhere
         ▼
  Docker Hub (registry)
         │
         │  Image is now: image + signature artifact
         ▼
  Done.
```

---

## 5) The Pipeline Signing Step

```yaml
# image_scan job in CI-CD.yml
permissions:
  id-token: write    # REQUIRED — allows the runner to request an OIDC token from GitHub
  contents: read

steps:
  - name: cosign-installer
    uses: sigstore/cosign-installer@v4.0.0
    # Installs the cosign binary on the runner

  - name: push Docker images
    uses: docker/build-push-action@v6.18.0
    id: push_step                           # give this step an id to reference its outputs
    with:
      push: true
      tags: ${{ vars.DOCKERHUB_USERNAME }}/rs-${{ matrix.app }}:${{github.sha}}

  - name: Sign the published Docker images
    env:
      DIGEST: ${{ steps.push_step.outputs.digest }}   # sha256:abc123... from the push step
    run: |
      cosign sign --yes "${{ vars.DOCKERHUB_USERNAME }}/rs-${{ matrix.app }}@${{env.DIGEST}}"
```

### Why sign `image@digest` not `image:tag`

```bash
# This signs the tag — tag is mutable, attacker can overwrite it:
cosign sign myorg/rs-cart:abc123sha   # BAD

# This signs the digest — digest is immutable, computed from image content:
cosign sign myorg/rs-cart@sha256:3f4a2b...   # GOOD
```

The digest `sha256:3f4a2b...` is the SHA-256 hash of the image manifest. It is computed from the actual bytes of the image. If a single byte of the image changes, the digest changes. Signing the digest means the signature is permanently bound to exactly that image content — not the tag name.

`steps.push_step.outputs.digest` is the digest emitted by `docker/build-push-action` immediately after pushing. It captures the digest at the moment of push, so there is no race condition between push and sign.

### The `--yes` flag

```bash
cosign sign --yes ...
```

Without `--yes`, cosign asks interactively: "Are you sure you want to push this signature to the public Rekor transparency log?" In a non-interactive CI environment, this prompt would hang forever. `--yes` auto-confirms it.

---

## 6) Rekor: The Transparency Log

Rekor is the most important security primitive in this system. It is a **publicly readable, append-only, cryptographically tamper-evident log** of all signing events.

### Why "append-only" matters

Rekor is built on **Merkle trees** — the same data structure used in blockchain and certificate transparency. Every new entry updates the tree root (`treeHash`). If you try to delete or modify any past entry, the tree root changes, and any subsequent root verification would fail. This makes historical tampering detectable.

### What gets written to Rekor

Every `cosign sign` call writes an entry like:

```json
{
  "logIndex": 123456789,
  "logID": "c0d23d6ad406973f9559f3ba2d1ca01f84147d8ffc5b8445c224f98b9591801d",
  "integratedTime": 1708689600,
  "body": {
    "kind": "hashedrekord",
    "spec": {
      "signature": {
        "content": "<base64 signature bytes>",
        "publicKey": {
          "content": "<base64 DER-encoded public key>"
        }
      },
      "data": {
        "hash": {
          "algorithm": "sha256",
          "value": "3f4a2b..."   // the image digest that was signed
        }
      }
    }
  }
}
```

### The Signed Entry Timestamp (SET)

Rekor also returns a **SET** — a signed timestamp proving that this entry existed in the log at a specific time. Kyverno uses the SET during verification to confirm:
1. The signature was published to Rekor (it wasn't just a local signature never logged),
2. The log entry timestamp is recent enough (within the certificate's validity window),
3. The Rekor log has not been tampered with since the entry was written.

### Querying Rekor for an image

```bash
# Search Rekor for all signatures for a specific image digest
rekor-cli search --sha sha256:3f4a2b...

# Get a specific log entry
rekor-cli get --log-index 123456789

# Verify cosign locally (bypasses Kyverno — useful for debugging)
cosign verify \
  --certificate-identity-regexp "https://github.com/abdelrahman-shebl/Robot-Shop-Microservices/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  docker.io/shebl22/rs-cart@sha256:3f4a2b...
```

---

## 7) How Kyverno Verifies the Signature

When Kyverno intercepts a pod creation request for an image matching `docker.io/shebl22/rs-*`, it runs through this verification chain:

```
  Pod CREATE request arrives at Kyverno
         │
         │  1. Extract image reference from pod spec
         │     e.g., docker.io/shebl22/rs-cart@sha256:3f4a2b...
         ▼
  Kyverno fetches the OCI signature artifact from Docker Hub
         │
         │  2. The signature is stored as an OCI artifact alongside the image
         │     Tag: sha256-3f4a2b....sig
         ▼
  Kyverno fetches the Rekor entry for this signature
         │
         │  3. Verifies the Signed Entry Timestamp (SET) — confirms it is in the log
         ▼
  Kyverno extracts the signing certificate from the Rekor entry
         │
         │  4. Checks the certificate chain up to Fulcio's root CA
         │  5. Verifies the certificate has not expired (it doesn't need to be valid NOW
         │     because Rekor's SET proves it WAS valid AT signing time)
         ▼
  Kyverno checks the certificate's identity fields against the policy
         │
         │  6. SubjectAltName must match subjectRegExp:
         │     "https://github.com/abdelrahman-shebl/Robot-Shop-Microservices/
         │      .github/workflows/CI-CD.yml@.*"
         │
         │  7. OIDC issuer must match issuer:
         │     "https://token.actions.githubusercontent.com"
         ▼
  Both match → pod is ALLOWED
  Either fails → pod is DENIED with:
    "image signature verification failed: no matching signatures"
```

### The short-lived certificate problem (and why it is not a problem)

Fulcio certificates expire in 10 minutes. Long after signing, the certificate is expired. This seems like it would break verification. It does not, because of **Rekor's inclusion proof**:

- Rekor recorded the entry when the certificate was valid.
- Rekor's SET (Signed Entry Timestamp) proves this entry was logged at time T.
- At time T, the certificate was valid.
- Therefore the signature was valid when made.

The certificate does not need to be valid at verification time — only at signing time. Rekor's log is the proof.

---

## 8) What the Full Trust Chain Looks Like

```
  Image: docker.io/shebl22/rs-cart@sha256:3f4a2b

         ← signed by →

  Ephemeral key pair (discarded after signing)

         ← certified by →

  Fulcio Certificate
    SubjectAltName: "...CI-CD.yml@refs/heads/main"
    OIDCIssuer: "https://token.actions.githubusercontent.com"
    Validity: 10 minutes
    Issued to: the ephemeral public key

         ← issued because →

  GitHub OIDC Token (JWT, signed by GitHub)
    sub: "repo:org/repo:...workflow:CI-CD.yml"
    iss: "https://token.actions.githubusercontent.com"

         ← permanently recorded in →

  Rekor Log Entry (append-only, tamper-evident)
    Includes: signature, certificate, image digest, timestamp, SET

         ← verified by →

  Kyverno (ImageValidatingPolicy)
    Checks: subjectRegExp + issuer against certificate identity
    Checks: Rekor inclusion proof (SET)
    Checks: Fulcio CA chain
```

If any link in this chain is broken, verification fails and the pod does not run.

---

## 9) Security Properties This Gives You

| Property | How it is achieved |
|----------|--------------------|
| Only CI-built images run | Kyverno blocks unsigned images; signature requires OIDC from GitHub CI |
| Signatures cannot be forged | Forging requires GitHub's OIDC private key (impossible from outside GitHub) |
| Signing event is permanently auditable | Rekor's append-only log records every signing event forever |
| Tampered images are caught | Signature is over the digest — any byte change breaks the signature |
| Short-lived credentials prevent replay | OIDC tokens expire in 10 minutes; ephemeral keys are discarded |
| No secrets to manage | No private key file in CI/CD; identity replaces keys entirely |

---

## 10) Required GitHub Actions Permissions

The signing step requires OIDC token issuance at the job level:

```yaml
image_scan:
  permissions:
    id-token: write    # allows requesting an OIDC token from GitHub
    contents: read     # allows reading the repo
```

If `id-token: write` is missing, cosign cannot get an OIDC token and Fulcio cannot issue a certificate. The signing step will fail with:

```
error: getting credentials: no token was found
```

At the repository or organization level, OIDC must not be disabled. Check: Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests" and OIDC settings.
