# DefectDojo

---

## 1) What DefectDojo Is

DefectDojo is an open-source **vulnerability management and security orchestration platform**. Its core job is to be the single place where all security scan results from your entire pipeline land, get deduplicated, tracked, and managed.

### The problem it solves

In a typical DevSecOps pipeline, security tools run at different stages:
- SAST (Static Application Security Testing) — e.g., Semgrep, Bandit, SonarQube
- DAST (Dynamic Application Security Testing) — e.g., OWASP ZAP, Burp Suite
- SCA (Software Composition Analysis) — e.g., Trivy, Snyk, OWASP Dependency-Check
- Container scanning — e.g., Trivy, Grype, Twistlock
- Infrastructure scanning — e.g., Checkov, tfsec, Prowler

Each tool produces its own output format (JSON, XML, CSV, HTML). Without a central platform, findings scatter across CI/CD logs, nobody tracks remediation, and the same vulnerability can be reported dozens of times by different tools.

DefectDojo solves this by:
1. **Ingesting** scan results from over 200 tools via importers.
2. **Deduplicating** findings — the same vulnerability found by three scanners appears once.
3. **Tracking remediation** — findings have statuses (Active, Risk Accepted, False Positive, Mitigated).
4. **Organizing by Product/Engagement** — maps findings to products, releases, and test engagements.
5. **Integrating with CI/CD** — REST API and CLI tools push scan results from pipelines automatically.

---

## 2) Architecture

The DefectDojo Helm chart deploys multiple components that work together:

```
  Browser / CI-CD pipeline
       │
       │  HTTPS (via Traefik)
       ▼
  ┌─────────────────────────────────────┐
  │  Django (uWSGI)                     │  ← Web interface + REST API + User login
  │  replicas: 1 (scale up if needed)  │
  └───────────────┬─────────────────────┘
                  │
          ┌───────┴────────┐
          │                │
          ▼                ▼
  ┌──────────────┐  ┌──────────────────────┐
  │  Celery      │  │  PostgreSQL          │  ← All vulnerability data lives here
  │  (workers)   │  │  (primary database)  │
  └──────┬───────┘  └──────────────────────┘
         │
         ▼
  ┌──────────────┐
  │  Valkey      │  ← Message broker between Django and Celery
  │  (Redis)     │    (formerly Redis, Valkey is the open-source fork)
  └──────────────┘
```

### Component responsibilities

| Component | Role |
|-----------|------|
| **Django / uWSGI** | Serves the web UI and REST API. Handles authentication, user management, and scan upload requests. When you upload a scan file, Django receives it and queues a Celery task. |
| **Celery workers** | Background task processor. Parses uploaded scan files, runs deduplication logic, correlates findings. This is the component that does the heavy lifting — large scan imports run entirely in Celery. |
| **PostgreSQL** | The persistent store for all findings, products, engagements, users, and settings. |
| **Valkey (Redis)** | The message broker between Django and Celery. Django pushes tasks to Valkey; Celery workers pull from it. Also used for session caching. |

---

## 3) The OOMKilled Problem

The most common issue when deploying DefectDojo is Django or uWSGI being killed with `OOMKilled` status shortly after the pod starts — particularly when a user logs in.

### Why login causes OOM

DefectDojo uses Django's default password hasher: **PBKDF2**. This is an intentionally slow cryptographic algorithm designed to resist brute-force attacks. PBKDF2 uses many iterations of SHA256, which is:
- CPU-intensive (expected)
- Temporarily memory-intensive during the hashing operation

When a user logs in, Django hashes their password and compares the result. If the pod's memory limit is too low, the hasher exceeds the limit and the OS kills the container. The pod shows `OOMKilled` in `kubectl describe pod`.

### The fix

Give Django and uWSGI enough memory headroom:

```yaml
django:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi    # 2Gi minimum to survive password hashing
  uwsgi:
    resources:
      limits:
        memory: 2Gi  # must match or exceed the Django limit
    appSettings:
      processes: 2   # reduce worker count to lower baseline memory footprint
      threads: 2
```

---

## 4) Secrets Management

DefectDojo has three sets of credentials that all reference a single Kubernetes Secret named `defectdojo`:

| Secret key | Used by |
|------------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL application user password |
| `POSTGRES_POSTGRES_PASSWORD` | PostgreSQL superuser (`postgres`) password |
| `VALKEY_PASSWORD` | Valkey/Redis broker password |
| `DD_SECRET_KEY` | Django secret key (CSRF, session signing) |
| `DD_CREDENTIAL_AES_256_KEY` | AES-256 key for encrypting stored credentials |

### How to pre-create the secret (ESO approach)

In this project, secrets come from AWS Secrets Manager via External Secrets Operator:

```yaml
# ExternalSecret fetches from AWS Secrets Manager and creates the 'defectdojo' secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: defectdojo-secrets
  namespace: defectdojo
spec:
  secretStoreRef:
    name: aws-secrets-store
    kind: ClusterSecretStore
  target:
    name: defectdojo           # creates a secret named 'defectdojo'
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: defectdojo/db
        property: POSTGRES_PASSWORD
    - secretKey: POSTGRES_POSTGRES_PASSWORD
      remoteRef:
        key: defectdojo/db
        property: POSTGRES_POSTGRES_PASSWORD
    - secretKey: VALKEY_PASSWORD
      remoteRef:
        key: defectdojo/valkey
        property: VALKEY_PASSWORD
    - secretKey: DD_SECRET_KEY
      remoteRef:
        key: defectdojo/app
        property: DD_SECRET_KEY
    - secretKey: DD_CREDENTIAL_AES_256_KEY
      remoteRef:
        key: defectdojo/app
        property: DD_CREDENTIAL_AES_256_KEY
```

### Values flags that disable chart-managed secrets

```yaml
createSecret: false           # do NOT let the chart create the 'defectdojo' secret
createValkeySecret: false     # do NOT let the chart create the Valkey secret
createPostgresqlSecret: false # do NOT let the chart create the PostgreSQL secret
```

Setting all three to `false` tells the chart to assume all secrets already exist. The chart then references them by name without creating them. **If these secrets do not exist when the pods start, all containers will crash with authentication errors.**

---

## 5) Full Values Walkthrough

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# SECRETS
# ─────────────────────────────────────────────────────────────────────────────

# Disable chart-managed secrets — use the pre-existing 'defectdojo' secret instead.
# This secret is created externally (e.g., via ESO pulling from AWS Secrets Manager).
createSecret: false
createValkeySecret: false
createPostgresqlSecret: false

# ─────────────────────────────────────────────────────────────────────────────
# ADMIN USER
# ─────────────────────────────────────────────────────────────────────────────
admin:
  user: admin
  password: ""     # leave empty when using an existing secret — set at first init

host: "defectdojo.yourdomain.com"
siteUrl: "https://defectdojo.yourdomain.com"

# ─────────────────────────────────────────────────────────────────────────────
# DJANGO (Web + API)
# ─────────────────────────────────────────────────────────────────────────────
django:
  replicas: 1      # scale to 2+ for high availability (needs shared session storage)
  
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi   # never go below 2Gi — login OOMKill otherwise

  uwsgi:
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 2000m
        memory: 2Gi  # must match or exceed django.resources.limits.memory
    
    appSettings:
      processes: 2   # number of uWSGI worker processes
      threads: 2     # threads per process (2×2 = 4 concurrent request handlers)
      # Default is 4 processes × 4 threads = 16 concurrent handlers
      # Reducing this cuts baseline RAM by ~40%

  ingress:
    enabled: true
    ingressClassName: "traefik"
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    tls:
      - secretName: defectdojo-tls
        hosts:
          - "defectdojo.yourdomain.com"
    hosts:
      - "defectdojo.yourdomain.com"

# ─────────────────────────────────────────────────────────────────────────────
# CELERY (Background Workers)
# ─────────────────────────────────────────────────────────────────────────────
celery:
  replicas: 1      # scale to 2+ for parallel scan processing
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"   # scan imports can be large — give it room
      cpu: "1000m"

# ─────────────────────────────────────────────────────────────────────────────
# POSTGRESQL
# ─────────────────────────────────────────────────────────────────────────────
postgresql:
  auth:
    username: defectdojo
    database: defectdojo
    
    # Point to the pre-existing 'defectdojo' secret
    existingSecret: "defectdojo"
    
    secretKeys:
      # Map which keys in the secret hold which passwords
      adminPasswordKey: "POSTGRES_POSTGRES_PASSWORD"  # the 'postgres' superuser
      userPasswordKey: "POSTGRES_PASSWORD"             # the 'defectdojo' app user
  
  primary:
    persistence:
      enabled: true
      storageClass: "gp3"
      size: 1Gi     # small for dev; set 20–50Gi for production
      # size: 20Gi

# ─────────────────────────────────────────────────────────────────────────────
# VALKEY (Message Broker)
# ─────────────────────────────────────────────────────────────────────────────
valkey:
  enabled: true
  architecture: standalone    # single instance; use replication for HA
  auth:
    existingSecret: "defectdojo"              # same secret as everything else
    existingSecretPasswordKey: "VALKEY_PASSWORD"
  primary:
    persistence:
      enabled: false   # no disk needed for the message broker
      # enabled: true  # enable in production to survive pod restarts without losing queued tasks
      # storageClass: "gp3"
      # size: 1Gi
```

---

## 6) Scaling and Production Considerations

### Django replicas

```yaml
django:
  replicas: 2   # for HA; both pods connect to the same PostgreSQL and Valkey
```

Django is stateless (sessions stored in Valkey), so horizontal scaling works out of the box.

### Celery replicas

```yaml
celery:
  replicas: 2   # parallel scan processing — useful when many pipelines push results simultaneously
```

Celery workers pull tasks from the Valkey queue independently, so scaling is simply adding more workers.

### PostgreSQL disk size

Start with at least 20Gi for any real usage. A heavily-used DefectDojo with years of scan history can grow to 100+ GB.

```yaml
postgresql:
  primary:
    persistence:
      size: 20Gi
```

### Enabling Valkey persistence

If Celery has a backlog of import tasks in the queue and the Valkey pod restarts, those tasks are lost. Enable persistence to prevent this:

```yaml
valkey:
  primary:
    persistence:
      enabled: true
      storageClass: "gp3"
      size: 1Gi
```

---

## 7) API-Driven Scan Import (CI/CD Integration)

The main value of DefectDojo is its API. Pipelines send scan results automatically:

```bash
# Minimal API import example (using curl directly)
curl -X POST "https://defectdojo.yourdomain.com/api/v2/import-scan/" \
  -H "Authorization: Token <api_token>" \
  -F "scan_type=Trivy Scan" \
  -F "file=@trivy-results.json" \
  -F "product_name=robot-shop" \
  -F "engagement_name=CI-$(git rev-parse --short HEAD)" \
  -F "auto_create_context=True"
```

In a real pipeline (GitHub Actions, GitLab CI), this happens automatically after every security scan step. DefectDojo deduplicates the findings — if the same CVE was reported in the last 10 scans, it appears once with a history, not 10 separate findings.
