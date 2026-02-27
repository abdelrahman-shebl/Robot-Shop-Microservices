# Robot Shop — Production DevSecOps Platform

A microservices e-commerce application evolved into a **full production-grade DevSecOps platform** on AWS — covering CI/CD pipelines, GitOps, infrastructure as code, FinOps, observability, and supply-chain security.

> Originally based on [Stan's Robot Shop](https://github.com/instana/robot-shop) — completely re-engineered with a production Kubernetes stack.

<p align="center">
  <img src="Images/Robot-Shop-Diagaram.jpeg" alt="Robot Shop Architecture" width="100%"/>
</p>

---

## Table of Contents

- [The Application](#-the-application)
- [Running the Project](#-running-the-project)
- [CI/CD Pipeline — DevSecOps](#-cicd-pipeline--devsecops)
- [Cloud Infrastructure — Terraform](#%EF%B8%8F-cloud-infrastructure--terraform)
- [GitOps — ArgoCD](#-gitops--argocd)
- [Platform Charts](#-platform-charts)
- [Zero Git Secrets — SSM + ESO](#-zero-git-secrets--ssm--eso)
- [Project Structure](#-project-structure)
- [Documentation](#-documentation)
- [License](#-license)

---

## 🛒 The Application

Stan's Robot Shop is a **12-microservice e-commerce application** built with a polyglot stack:

<!-- ARCHITECTURE DIAGRAM -->
<p align="center">
  <img src="Images/RobotShopArchitecture.jpeg" alt="Robot Shop Architecture" width="100%"/>
</p>

| Service | Technology | Role |
|---------|-----------|------|
| **web** | Nginx | Reverse proxy & frontend gateway |
| **catalogue** | Node.js (Express) | Product catalog from MongoDB |
| **user** | Node.js (Express) | User auth & sessions (MongoDB + Redis) |
| **cart** | Node.js (Express) | Shopping cart (Redis) |
| **shipping** | Java (Spring Boot) | Shipping calculation (MySQL) |
| **payment** | Python (Flask) | Payment processing (RabbitMQ) |
| **ratings** | PHP (Apache) | Product ratings (MySQL) |
| **dispatch** | Go | Async order processing (RabbitMQ consumer) |
| **mongodb** | MongoDB | Document store for catalogue & users |
| **mysql** | MySQL | Relational store for shipping & ratings |
| **redis** | Redis | Session cache & cart storage |
| **rabbitmq** | RabbitMQ | Message broker for async order flow |

<details>
<summary><b>Service Communication Map</b></summary>

| Source | Destination | Protocol |
|--------|-------------|----------|
| web | catalogue, user, cart, shipping, payment, ratings | HTTP |
| catalogue | mongodb | MongoDB driver |
| user | mongodb, redis | MongoDB driver, Redis |
| cart | redis, catalogue | Redis, HTTP |
| shipping | mysql, cart | JDBC, HTTP |
| ratings | mysql | PDO |
| payment | rabbitmq, cart, user | AMQP, HTTP |
| dispatch | rabbitmq | AMQP |

</details>

<details>
<summary><b>Robot Shop in Action</b></summary>

![Robot Shop](Images/Robot-Shop/Robot-Shop_final.png)

</details>

---

## 🚀 Running the Project

There are **three ways** to run this project, from simplest to full production:

### Option 1 — Docker Compose (Local Development)

The fastest way to get the app running locally.

```bash
# 1. Set up environment
cp .env.example .env
nano .env  # Set your credentials

# 2. Start all services
docker-compose up -d

# 3. Access the store
open http://localhost:8080

# 4. Tear down
docker-compose down -v
```

<details>
<summary><b>Docker Compose Network Architecture</b></summary>

The compose file segments services into **4 isolated networks**:

| Network | Purpose | Services |
|---------|---------|----------|
| **frontend** | Public web access | web |
| **api-services** | Backend APIs | web, catalogue, user, cart, shipping, payment, ratings |
| **data-services** | Databases | mongodb, redis, mysql + API services that need them |
| **message-queue** | Async messaging | rabbitmq, payment, dispatch |

Databases are **never exposed** to the host — only the `web` service on port 8080 is public.

</details>

### Option 2 — Helm Chart (Existing Cluster)

Deploy to any Kubernetes cluster using the umbrella Helm chart.

```bash
# 1. Add dependencies
cd helm/robot-shop && helm dependency build

# 2. Install — Dev environment
helm install robot-shop . \
  -n robotshop --create-namespace \
  -f values.yaml \
  -f values-dev.yaml

# 3. Install — Production environment
helm install robot-shop . \
  -n robotshop --create-namespace \
  -f values.yaml \
  -f values-prod.yaml
```

<details>
<summary><b>Dev vs Prod Environment Differences</b></summary>

| Dimension | Dev | Prod |
|-----------|-----|------|
| CPU requests / limits | 50m / 200m | 215m / 512m |
| Memory requests / limits | 200Mi / 500Mi | 512Mi / 750Mi |
| HPA min / max replicas | 1 / 2 | 2 / 6 |
| MySQL replicas | 1 | 3 |
| MongoDB replicas | 1 | 3 |
| Redis | standalone, 200Mi | master + 3 replicas, 512Mi |
| PVC storage | 200Mi | 512Mi |

Both environments use the same YAML anchor pattern (`&dev_apis_values` / `&prod_apis_values`) to DRY-configure all services.

</details>

### Option 3 — Full Infrastructure (Production)

Provision the entire AWS stack with Terraform, then let ArgoCD deploy everything via GitOps.

```bash
# 1. Configure variables
cd terraform
cp variables.example.yaml variables.yaml
nano variables.yaml  # Set all secrets

# 2. Deploy infrastructure
terraform init
terraform apply

# 3. Connect to cluster
aws eks update-kubeconfig --name eks-robot-shop --region us-east-1

# ArgoCD auto-deploys all charts — no manual helm install needed
# Access ArgoCD at: https://argocd.shebl22.me
# Access Robot Shop at: https://shebl22.me
```

---

## 🔄 CI/CD Pipeline — DevSecOps

The GitHub Actions pipeline (`.github/workflows/CI-CD.yml`) implements a full **DevSecOps** workflow with security scanning at every layer:

```
Push to main/feature/* 
    │
    ├── Semgrep (SAST) ──────────────── Static code analysis
    ├── Gitleaks ─────────────────────── Secret detection in code
    ├── Image Build + Scan (10 apps) ── Docker Scout (SCA + container security)
    │       ├── Build with BuildKit cache
    │       ├── Scan for CVEs (critical + high)
    │       ├── Push to Docker Hub
    │       └── Cosign keyless signing ── Supply-chain integrity (Sigstore)
    │
    ├── OWASP ZAP (DAST) ────────────── Runtime vulnerability scan
    │       ├── docker-compose up
    │       └── ZAP baseline scan on localhost:8080
    │
    ├── Consolidate Reports ──────────── Merge all SARIF/JSON into one bundle
    │
    └── Update K8s Values ────────────── yq updates image tag → git push [skip ci]
                                          └── ArgoCD detects change → deploys
```

### Security Scanning Tools

| Tool | Type | What It Catches |
|------|------|----------------|
| **Semgrep** | SAST | Code bugs, injection flaws, insecure patterns |
| **Gitleaks** | Secret Detection | API keys, passwords, tokens in source code |
| **Docker Scout** | SCA + Container | CVEs in OS packages and application dependencies |
| **OWASP ZAP** | DAST | XSS, SQL injection, misconfigurations at runtime |
| **Cosign** | Supply Chain | Keyless image signing via Sigstore transparency log |

### GitOps Auto-Deploy

The last pipeline stage uses `yq` to update the image tag in `helm/robot-shop/values.yaml` and pushes back with `[skip ci]`. ArgoCD watches this repo and auto-syncs the new version to the cluster.

---

## ☁️ Cloud Infrastructure — Terraform

All infrastructure is defined in `terraform/` using official AWS modules:

```
terraform/
├── main.tf          # EKS, VPC, Karpenter, Addons, IAM, Route53
├── variables.tf     # Cluster config (region, domain, EKS version)
├── outputs.tf       # Route53 nameservers
├── providers.tf     # AWS + Helm + Kubectl providers
└── modules/
    ├── addons/      # ArgoCD + ArgoCD Apps (deploys all charts)
    ├── karpenter/   # Karpenter Helm + NodePool + EC2NodeClass
    ├── ssm/         # AWS SSM Parameter Store (secrets)
    ├── eso/         # External Secrets Operator IAM
    ├── edns/        # External DNS IAM
    └── opencost/    # S3 + CUR + Glue + Athena for cost data
```

### What Gets Provisioned

| Resource | Details |
|----------|---------|
| **VPC** | 2 AZs, public + private subnets, NAT gateway |
| **EKS** | v1.35, API auth mode, managed node group for system workloads |
| **EKS Addons** | VPC-CNI, CoreDNS, kube-proxy, metrics-server, EBS CSI driver |
| **Karpenter** | Controller on system node group + Spot/On-Demand NodePools |
| **Route53** | Hosted zone for `shebl22.me` |
| **IAM Pod Identities** | cert-manager, External DNS, ESO, OpenCost, EBS CSI — all via EKS Pod Identity (not IRSA) |
| **SSM Parameters** | MySQL, MongoDB, DefectDojo, OpenCost credentials as SecureStrings |
| **OpenCost Infra** | S3 buckets, CUR report, Glue crawler + catalog, Athena workgroup |
| **ArgoCD** | Helm install + ArgoCD Apps that deploy everything else |

---

## 🔁 GitOps — ArgoCD

ArgoCD is installed by Terraform and then manages **all other platform components** through the App of Apps pattern:

<details>
<summary><b>ArgoCD Dashboard</b></summary>

![ArgoCD Login](Images/ArgoCD/Argo-login_final.png)
![ArgoCD Apps Overview](Images/ArgoCD/Argo-Apps1.png)
![ArgoCD Apps Detail](Images/ArgoCD/Argo-Apps2.png)
![ArgoCD Apps Chart](Images/ArgoCD/Argo-Apps-chart.png)

</details>

### Deployment Order (Sync Waves)

ArgoCD deploys charts in a deterministic order using sync waves:

| Wave | Charts | Purpose |
|------|--------|---------|
| **-5** | cert-manager | TLS certificate management |
| **-4** | cert-manager-manifests | ClusterIssuer + Certificate resources |
| **-3** | Traefik, External DNS, ESO, kube-prometheus-stack, Grafana dashboards, DefectDojo | Core platform services |
| **-2** | MySQL/MongoDB exporters, OpenCost, Goldilocks, Kyverno | Observability + policy |
| **-1** | Kyverno manifests | Image signing policy |
| **0** | Robot Shop (umbrella chart) | The application itself |

All ArgoCD Applications use `resources-finalizer.argocd.argoproj.io` for clean cascade deletion on `terraform destroy`.

---

## 📦 Platform Charts

Each chart deployed by ArgoCD introduces a specific capability. Click to expand details.

<details>
<summary><b>🔒 Cert-Manager — TLS Certificates</b></summary>

**What:** Automates TLS certificate issuance and renewal using Let's Encrypt.

**How:** DNS-01 challenge via Route53 (using EKS Pod Identity). Two ClusterIssuers: production and staging.

**Certificates issued for:**
- `shebl22.me` (Robot Shop)
- `argocd.shebl22.me`
- `dojo.shebl22.me`
- `goldilocks.shebl22.me`
- `monitoring.shebl22.me` (Grafana)
- `opencost.shebl22.me`

> 📖 [Detailed Documentation](Documentation/Charts/Cert-Manager/Cert-Manager.md)

</details>

<details>
<summary><b>🌐 Traefik — Ingress Controller</b></summary>

**What:** Cloud-native ingress controller that routes external traffic to services via IngressRoute or standard Ingress resources.

**How:** Deployed as an AWS NLB (Network Load Balancer). Handles TLS termination with cert-manager certificates.

**Endpoints:**
- `https://shebl22.me` → Robot Shop web service
- `https://argocd.shebl22.me` → ArgoCD dashboard
- `https://dojo.shebl22.me` → DefectDojo
- `https://monitoring.shebl22.me` → Grafana
- `https://opencost.shebl22.me` → OpenCost UI
- `https://goldilocks.shebl22.me` → Goldilocks dashboard

> 📖 [Detailed Documentation](Documentation/Charts/Traefik/Traefik.md)

</details>

<details>
<summary><b>🌍 External DNS — Automatic DNS Records</b></summary>

**What:** Automatically creates and manages Route53 DNS records from Kubernetes Ingress/Service resources.

**How:** Watches Ingress resources and syncs A/CNAME records to the `shebl22.me` hosted zone using EKS Pod Identity for Route53 access.

> 📖 [Detailed Documentation](Documentation/Charts/EDNS/EDNS.md)

</details>

<details>
<summary><b>🔑 External Secrets Operator (ESO) — Secret Sync</b></summary>

**What:** Syncs secrets from AWS SSM Parameter Store into Kubernetes Secrets — **zero secrets in Git**.

**How:** A `ClusterSecretStore` points to AWS ParameterStore. `ExternalSecret` resources pull credentials every 1 hour into target namespaces.

| SSM Parameter | K8s Secret | Namespace |
|---------------|-----------|-----------|
| `/prod/mysql/credentials` | `mysql-secrets` | robotshop |
| `/prod/mongo/credentials` | `mongo-secrets` | robotshop |
| `/prod/dojo/credentials` | `defectdojo` | dojo |
| `/prod/opencost/cloud-integration` | `cloud-integration` | opencost |

> 📖 [Detailed Documentation](Documentation/Charts/ESO/ESO.md)

</details>

<details>
<summary><b>📊 Kube-Prometheus-Stack — Observability</b></summary>

**What:** Full monitoring stack — Prometheus for metrics collection, Grafana for visualization, Alertmanager for alerting.

**Includes:**
- Prometheus server with ServiceMonitors for MySQL and MongoDB exporters
- Grafana at `monitoring.shebl22.me` with pre-loaded dashboards
- Node Exporter for host-level metrics
- kube-state-metrics for cluster state

<details>
<summary><h1>Screenshots</h1></summary>

![Prometheus](Images/Prometheus/Prometheus_final.png)
![Grafana Login](Images/Grafana/Grafana%20login_final.png)
![Grafana Dashboards](Images/Grafana/Dashboards.png)
![K8s Cluster Dashboard](Images/Grafana/k8s-cluster-dashboard.png)
![Node Exporter 1](Images/Grafana/Node-Exporter-dashboard-1.png)
![Node Exporter 2](Images/Grafana/Node-Exporter-dashboard-2.png)
![MongoDB Dashboard](Images/Grafana/Mongo-dashboard.png)
![MySQL Dashboard](Images/Grafana/Mysql-dashboard.png)
![OpenCost Dashboard 1](Images/Grafana/OpenCost-dashboard-1.png)
![OpenCost Dashboard 2](Images/Grafana/OpenCost-dashboard-2.png)
![OpenCost Dashboard 3](Images/Grafana/OpenCost-dashboard-3.png)
![OpenCost Dashboard 4](Images/Grafana/OpenCost-dashboard-4.png)
![OpenCost Dashboard 5](Images/Grafana/OpenCost-dashboard-5.png)
![OpenCost Dashboard 6](Images/Grafana/OpenCost-dashboard-6.png)
![OpenCost Dashboard 7](Images/Grafana/OpenCost-dashboard-7.png)
![OpenCost Dashboard 8](Images/Grafana/OpenCost-dashboard-8.png)
![OpenCost Dashboard 9](Images/Grafana/OpenCost-dashboard-9.png)
![OpenCost Dashboard 10](Images/Grafana/OpenCost-dashboard-10.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/Kube-Prometheus-Stack/kube-prometheus-stack.md) · [ServiceMonitors](Documentation/Charts/Kube-Prometheus-Stack/ServiceMonitors.md)

</details>

<details>
<summary><b>🛡️ DefectDojo — Vulnerability Management</b></summary>

**What:** Centralized platform to **aggregate, deduplicate, and track** all security findings from the CI/CD pipeline (Semgrep, Gitleaks, Docker Scout, ZAP reports).

**How:** Deployed at `dojo.shebl22.me`. Pipeline reports can be imported to visualize vulnerabilities across all services in one dashboard.

<details>
<summary><h1>Screenshots</h1></summary>

![DefectDojo 1](Images/DefectDojo/DD1.png)
![DefectDojo 1 Highlighted](Images/DefectDojo/DD1_final.png)
![DefectDojo 2](Images/DefectDojo/DD2.png)
![DefectDojo 3](Images/DefectDojo/DD3.png)
![DefectDojo 4](Images/DefectDojo/DD4.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/DefectDojo/defectdojo.md) · [Pipeline Integration](Documentation/Charts/DefectDojo/DefectDojo-Pipeline.md)

</details>

<details>
<summary><b>💰 OpenCost — FinOps & Cost Visibility</b></summary>

**What:** Real-time Kubernetes cost monitoring — breaks down spending by namespace, deployment, pod, and label.

**How:** Integrates with AWS Cost & Usage Reports via Athena for accurate cloud cost allocation. Terraform provisions S3 buckets, CUR, Glue crawler, and Athena workgroup. OpenCost reads this data through a cloud integration secret synced by ESO.

**Also includes Grafana dashboards** showing cost breakdowns per service:

<details>
<summary><h1>Screenshots</h1></summary>

![OpenCost UI](Images/OpenCost/OpenCost-1_final.png)
![OpenCost 2](Images/OpenCost/OpenCost-2.png)
![OpenCost 3](Images/OpenCost/OpenCost-3.png)
![OpenCost 4](Images/OpenCost/OpenCost-4.png)
![OpenCost 5](Images/OpenCost/OpenCost-5.png)
![OpenCost 6](Images/OpenCost/OpenCost-6.png)
![OpenCost 7](Images/OpenCost/OpenCost-7.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/OpenCost/opencost.md)

</details>

<details>
<summary><b>📐 Goldilocks — Resource Right-Sizing</b></summary>

**What:** Provides resource **request and limit recommendations** based on actual usage data from VPA (Vertical Pod Autoscaler).

**How:** Analyzes workload metrics and shows a dashboard at `goldilocks.shebl22.me` with per-container CPU/memory suggestions — helping avoid over-provisioning.

<details>
<summary><h1>Screenshots</h1></summary>

![Goldilocks 1](Images/Goldilocks/goldilocks-1_final.png)
![Goldilocks 2](Images/Goldilocks/goldilocks-2.png)
![Goldilocks 3](Images/Goldilocks/goldilocks-3.png)
![Goldilocks 4](Images/Goldilocks/goldilocks-4.png)
![Goldilocks 5](Images/Goldilocks/goldilocks-5.png)
![Goldilocks 6](Images/Goldilocks/goldilocks-6.png)
![Goldilocks 7](Images/Goldilocks/goldilocks-7.png)
![Goldilocks 8](Images/Goldilocks/goldilocks-8.png)
![Goldilocks 9](Images/Goldilocks/goldilocks-9.png)
![Goldilocks 10](Images/Goldilocks/goldilocks-10.png)
![Goldilocks 11](Images/Goldilocks/goldilocks-11.png)
![Goldilocks 12](Images/Goldilocks/goldilocks-12.png)
![Goldilocks 13](Images/Goldilocks/goldilocks-13.png)
![Goldilocks 14](Images/Goldilocks/goldilocks-14.png)
![Goldilocks 15](Images/Goldilocks/goldilocks-15.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/Goldilocks/goldilocks.md)

</details>

<details>
<summary><b>🛡️ Kyverno — Policy Engine & Image Verification</b></summary>

**What:** Kubernetes-native policy engine that enforces **Cosign keyless image signature verification** — only images signed by the CI/CD pipeline can run in the cluster.

**How:** An `ImageValidatingPolicy` requires all `docker.io/shebl22/rs-*` images to have a valid Cosign signature from the GitHub Actions OIDC identity. Unsigned or tampered images are **rejected at admission**.

<details>
<summary><h1>Screenshots</h1></summary>

![Kyverno 1](Images/Kyverno/Kyverno-1.png)
![Kyverno 2](Images/Kyverno/Kyverno-2.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/kyverno/kyverno.md) · [Cosign + Sigstore](Documentation/Charts/kyverno/Cosign-Sigstore.md)

</details>

<details>
<summary><b>⚡ Karpenter — Spot-First Node Provisioning</b></summary>

**What:** Kubernetes-native node autoscaler that provisions the **right nodes at the right time** — using **Spot instances by default** for up to 90% cost savings.

**Architecture:**
- **System Node Group** (managed, on-demand `c7i-flex.large`): Runs Karpenter controller, CoreDNS, and system add-ons with a `workload-type=system` taint
- **Spot Pool** (weight 100 — primary): `t3.small/medium/large`, `c7i-flex.large`, `m7i-flex.large`
- **On-Demand Pool** (weight 10 — fallback): `t3.large/xlarge` — used only when Spot is unavailable

| Config | Value |
|--------|-------|
| AMI | Amazon Linux 2023 |
| Consolidation | `WhenEmptyOrUnderutilized` (10s) |
| Node expiry | 168h (7 days) |
| Limits per pool | 50 CPU, 200Gi RAM |

<details>
<summary><h1>Screenshots</h1></summary>

![Karpenter 1](Images/Karpenter/Karpenter-1.png)
![Karpenter 2](Images/Karpenter/Karpenter-2.png)
![Karpenter 3](Images/Karpenter/Karpenter-3.png)

</details>

> 📖 [Detailed Documentation](Documentation/Charts/Karpenter/Karpenter.md) · [NodePool & NodeClass](Documentation/Charts/Karpenter/Karpenter-NodePool-NodeClass.md)

</details>

---

## 🔐 Zero Git Secrets — SSM + ESO

**No credentials are stored in Git.** The secret flow is:

```
Terraform                       AWS                         Kubernetes
─────────                       ───                         ──────────
variables.yaml ──► SSM Module ──► SSM Parameter Store ──► ESO ──► K8s Secrets
  (git-ignored)      (stores)     (/prod/mysql/...)       (syncs)   (in-cluster)
```

1. **Terraform** reads credentials from `variables.yaml` (git-ignored) and stores them in **AWS SSM Parameter Store** as SecureStrings
2. **EKS Pod Identity** grants the ESO pod IAM permissions to read those SSM parameters
3. **External Secrets Operator** periodically (1h) pulls SSM values and creates/updates native K8s Secrets
4. **Application pods** consume K8s Secrets as env vars or volume mounts — they never know about SSM

---

## 🔒 Kubernetes Security

### Helm Chart Security Features

The umbrella Helm chart uses a shared **library chart** (`_common`) that enforces security across all services:

**Pod Security Context** (every Deployment):
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 2000
  fsGroup: 3000
  seccompProfile:
    type: RuntimeDefault
```

**Container Security Context**:
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

**HPA** (Horizontal Pod Autoscaler) on all application services — scales on CPU and memory utilization.

**Network Policies** — Per-pod policies enforcing:
- Redis only accepts traffic from `user` and `cart` pods
- RabbitMQ only accepts traffic from `payment` and `dispatch` pods
- Databases only accept traffic from their specific consumer services
- All pods allow egress only to kube-dns + their required dependencies

### 4-Tier Network Policy Architecture

| Tier | Ingress From | Egress To |
|------|-------------|-----------|
| **Frontend** | Ingress controller only | Backend tier + DNS |
| **Backend** | Frontend + other backend | Database + message-queue + DNS |
| **Database** | Backend only | DNS only |
| **Message Queue** | Backend only | DNS only |

---

## 📁 Project Structure

```
robot-shop/
├── .github/workflows/CI-CD.yml     # DevSecOps pipeline
├── docker-compose.yaml              # Local development
│
├── cart/                            # Cart service (Node.js)
├── catalogue/                       # Catalogue service (Node.js)
├── dispatch/                        # Dispatch service (Go)
├── mysql/                           # MySQL init scripts
├── payment/                         # Payment service (Python)
├── ratings/                         # Ratings service (PHP)
├── shipping/                        # Shipping service (Java)
├── user/                            # User service (Node.js)
├── web/                             # Nginx frontend gateway
│
├── helm/robot-shop/                 # Umbrella Helm chart
│   ├── Chart.yaml                   #   Dependencies (Redis, RabbitMQ, all services)
│   ├── values.yaml                  #   Base values + image tags (updated by CI)
│   ├── values-dev.yaml              #   Dev overrides (low resources, 1 replica)
│   ├── values-prod.yaml             #   Prod overrides (HA, 2-6 replicas)
│   └── charts/                      #   Sub-charts:
│       ├── _common/                 #     Library chart (shared templates)
│       ├── web/                     #     Deployment + HPA + NetworkPolicy + Ingress
│       ├── cart/                    #     Deployment + HPA + NetworkPolicy
│       ├── catalogue/               #     Deployment + HPA + NetworkPolicy
│       ├── user/                    #     Deployment + HPA + NetworkPolicy
│       ├── payment/                 #     Deployment + HPA + NetworkPolicy
│       ├── shipping/                #     Deployment + HPA + NetworkPolicy
│       ├── dispatch/                #     Deployment + HPA + NetworkPolicy
│       ├── ratings/                 #     Deployment + HPA + NetworkPolicy
│       ├── mysql/                   #     StatefulSet + NetworkPolicy
│       └── mongodb/                 #     StatefulSet + NetworkPolicy
│
├── K8s/                             # Raw K8s manifests (deployed by ArgoCD)
│   ├── cert-manager/                #   ClusterIssuer + Certificate resources
│   ├── eso/                         #   ClusterSecretStore + ExternalSecrets
│   ├── kyverno/                     #   ImageValidatingPolicy (Cosign)
│   ├── grafana/                     #   Dashboard ConfigMaps
│   └── microservices/               #   Reference raw manifests
│
├── terraform/                       # Infrastructure as Code
│   ├── main.tf                      #   EKS, VPC, Karpenter, IAM, Route53
│   ├── variables.tf                 #   Cluster configuration
│   ├── variables.yaml               #   Secrets (git-ignored)
│   └── modules/
│       ├── addons/                  #   ArgoCD + ArgoCD Apps (deploys all charts)
│       ├── karpenter/               #   Helm + NodePool + EC2NodeClass
│       ├── ssm/                     #   AWS SSM Parameter Store
│       ├── eso/                     #   ESO IAM + Pod Identity
│       ├── edns/                    #   External DNS IAM
│       └── opencost/                #   S3 + CUR + Glue + Athena
│
├── Documentation/                   # Detailed docs per chart
└── Images/                          # Screenshots per tool
```

---

## 📖 Documentation

In-depth documentation for every component is available in the [`Documentation/`](Documentation/) directory:

| Category | Document | Description |
|----------|----------|-------------|
| **ArgoCD** | [ArgoCD](Documentation/Charts/ArgoCD/Argocd.md) · [ArgoCD Apps](Documentation/Charts/ArgoCD/Argocd-apps.md) | GitOps setup, app-of-apps pattern |
| **Cert-Manager** | [Cert-Manager](Documentation/Charts/Cert-Manager/Cert-Manager.md) | DNS-01 challenge, ClusterIssuers, certificates |
| **DefectDojo** | [DefectDojo](Documentation/Charts/DefectDojo/defectdojo.md) · [Pipeline](Documentation/Charts/DefectDojo/DefectDojo-Pipeline.md) | Vulnerability dashboard, CI integration |
| **External DNS** | [EDNS](Documentation/Charts/EDNS/EDNS.md) | Automatic Route53 record management |
| **ESO** | [ESO](Documentation/Charts/ESO/ESO.md) | SSM → K8s secret syncing |
| **Goldilocks** | [Goldilocks](Documentation/Charts/Goldilocks/goldilocks.md) | Resource right-sizing recommendations |
| **Karpenter** | [Karpenter](Documentation/Charts/Karpenter/Karpenter.md) · [NodePool & NodeClass](Documentation/Charts/Karpenter/Karpenter-NodePool-NodeClass.md) | Spot-first node provisioning |
| **Monitoring** | [kube-prometheus-stack](Documentation/Charts/Kube-Prometheus-Stack/kube-prometheus-stack.md) · [ServiceMonitors](Documentation/Charts/Kube-Prometheus-Stack/ServiceMonitors.md) | Prometheus + Grafana setup |
| **Kyverno** | [Kyverno](Documentation/Charts/kyverno/kyverno.md) · [Cosign + Sigstore](Documentation/Charts/kyverno/Cosign-Sigstore.md) | Image signature verification |
| **OpenCost** | [OpenCost](Documentation/Charts/OpenCost/opencost.md) | FinOps cost allocation with Athena |
| **Traefik** | [Traefik](Documentation/Charts/Traefik/Traefik.md) | Ingress controller configuration |
| **Helm** | [Templates Guide](Documentation/Helm_templates/Helm_templates.md) · [From Scratch](Documentation/Helm_templates/Deployment-Template-From-Scratch.md) | Helm template patterns |
| **Umbrella Chart** | [Umbrella](Documentation/Umbrella-Chart/Umbrella.md) · [Stages](Documentation/Umbrella-Chart/Umbrella-Stages.md) | Multi-chart architecture |
| **YAML Tricks** | [YAML Tricks](Documentation/Yaml_Tricks_and_shortcuts/Yaml_Tricks_and_shortcuts.md) | Anchors, merge keys, DRY patterns |

---

## 📄 License

See [LICENSE](LICENSE) file for details.
