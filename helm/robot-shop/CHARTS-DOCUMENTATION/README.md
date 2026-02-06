# Robot Shop Helm Charts - Complete Documentation

## 📚 Documentation Overview

This directory contains detailed guides for each Helm chart used in the robot-shop deployment. Each guide covers configuration, values, required AWS resources, IAM policies, Terraform modules, and troubleshooting.

---

## 📋 Chart Index

### 1. **Kube-Prometheus-Stack** - Monitoring & Observability
   - **File**: [01-KUBE-PROMETHEUS-STACK.md](01-KUBE-PROMETHEUS-STACK.md)
   - **Purpose**: Prometheus, Grafana, AlertManager deployment
   - **Key Features**:
     - ✅ Automatic metric collection (ServiceMonitor CRDs)
     - ✅ Pre-built Grafana dashboards
     - ✅ Alert routing with AlertManager
   - **Time to understand**: 30 minutes
   - **Complexity**: Medium
   - **Cost**: ~$50-100/month (storage dependent)

---

### 2. **Prometheus Exporters** - Database Metrics
   - **File**: [02-PROMETHEUS-EXPORTERS.md](02-PROMETHEUS-EXPORTERS.md)
   - **Components**:
     - prometheus-mysql-exporter
     - prometheus-mongodb-exporter
   - **Purpose**: Convert database metrics to Prometheus format
   - **Key Features**:
     - ✅ Pod labels for network policies
     - ✅ ServiceMonitor auto-discovery
     - ✅ Database connection pooling
   - **Time to understand**: 20 minutes
   - **Complexity**: Low
   - **Cost**: Minimal (runs on existing nodes)

---

### 3. **Traefik** - Ingress & TLS Termination
   - **File**: [03-TRAEFIK.md](03-TRAEFIK.md)
   - **Purpose**: Reverse proxy, ingress controller, automatic TLS
   - **Key Features**:
     - ✅ Native Let's Encrypt support
     - ✅ Automatic certificate renewal
     - ✅ HTTP → HTTPS redirect
     - ✅ Middleware support (compression, auth, etc.)
   - **Time to understand**: 25 minutes
   - **Complexity**: Low-Medium
   - **Cost**: ~$16-32/month (LoadBalancer)
   - **Why Traefik is easier than nginx-ingress + cert-manager**: See section 3 of guide

---

### 4. **External Secrets Operator (ESO)** - Secret Management
   - **File**: [04-EXTERNAL-SECRETS-OPERATOR.md](04-EXTERNAL-SECRETS-OPERATOR.md)
   - **Purpose**: Sync secrets from AWS Secrets Manager to Kubernetes
   - **Key Features**:
     - ✅ Automatic secret rotation
     - ✅ Pod Identity support (simpler than IRSA)
     - ✅ ExternalSecret & SecretStore CRDs
     - ✅ Template support (construct connection strings)
   - **Time to understand**: 40 minutes
   - **Complexity**: Medium-High
   - **Cost**: Minimal (API calls ~$0.05/month)
   - **AWS Resources**: IAM role, Secrets Manager secrets

---

### 5. **External DNS** - Automatic DNS Management
   - **File**: [05-EXTERNAL-DNS.md](05-EXTERNAL-DNS.md)
   - **Purpose**: Automatically create/update Route53 records from Ingress/Service
   - **Key Features**:
     - ✅ Domain filtering (safety)
     - ✅ TXT registry (ownership tracking)
     - ✅ Sync or upsert-only policies
     - ✅ Pod Identity authentication
   - **Time to understand**: 30 minutes
   - **Complexity**: Low-Medium
   - **Cost**: Minimal (Route53 change batch = $0.40 per 1M changes)
   - **AWS Resources**: IAM role, Route53 hosted zone

---

### 6. **Karpenter** - Node Auto-Scaling
   - **File**: [06-KARPENTER.md](06-KARPENTER.md)
   - **Purpose**: Intelligent cluster auto-scaling (faster than Cluster Autoscaler)
   - **Key Features**:
     - ✅ Fast scaling (20-30 seconds vs 1-2 minutes)
     - ✅ Spot instance support (70% cost savings)
     - ✅ Node consolidation
     - ✅ EC2NodeClass + NodePool CRDs
     - ✅ Graceful spot interruption handling
   - **Time to understand**: 60 minutes
   - **Complexity**: High
   - **Cost**: Savings typically 40-60% through spot instances
   - **AWS Resources**: IAM role, SQS queue, EC2 permissions, EventBridge rules
   - **Module**: terraform-aws-modules/eks/aws//modules/karpenter

---

### 7. **OpenCost** - Cost Visibility & Attribution
   - **File**: [07-OPENCOST.md](07-OPENCOST.md)
   - **Purpose**: Real-time Kubernetes cluster cost tracking
   - **Key Features**:
     - ✅ Cost per namespace/pod/container
     - ✅ AWS billing integration
     - ✅ Spot vs on-demand pricing
     - ✅ Web dashboard and API
   - **Time to understand**: 35 minutes
   - **Complexity**: Medium
   - **Cost**: Minimal
   - **AWS Resources**: IAM role, S3 bucket for spot data, EC2 Pricing API access
   - **Important**: 24-hour wait for S3 spot data availability

---

### 8. **Goldilocks** - Resource Right-Sizing
   - **File**: [08-GOLDILOCKS.md](08-GOLDILOCKS.md)
   - **Purpose**: Recommend optimal CPU/memory requests and limits
   - **Key Features**:
     - ✅ Analyzes 7+ days of actual usage
     - ✅ Provides recommendations (advisory only)
     - ✅ Estimates cost savings
     - ✅ Web dashboard
   - **Time to understand**: 25 minutes
   - **Complexity**: Low
   - **Cost**: Minimal
   - **Savings**: Typical 30-50% cost reduction through right-sizing
   - **Depends on**: Vertical Pod Autoscaler (VPA)

---

## 🚀 Quick Start Guide

### Estimated Deployment Time
```
1. Read overview of each chart: 3 hours
2. Set up AWS infrastructure: 2 hours
3. Deploy with Helm: 30 minutes
4. Verification and testing: 1 hour
─────────────────────────────────
Total: 6.5 hours (day 1)

Day 2-7: Monitor and optimize
```

### Prerequisites Checklist

```
Kubernetes Cluster:
  ☐ EKS cluster running (v1.24+)
  ☐ kubectl configured
  ☐ Helm 3.x installed
  ☐ Ingress controller ready (or use Traefik)

AWS Account:
  ☐ IAM permissions for policy creation
  ☐ Route53 hosted zone created
  ☐ S3 bucket for Terraform state
  ☐ EC2 permissions for Karpenter

DNS:
  ☐ Domain registered (shebl.com)
  ☐ Nameservers pointing to Route53 (if AWS)
  ☐ Email for Let's Encrypt notifications
```

---

## 📊 Architecture Diagram

```
                    ┌─ Internet ─────────────────────┐
                    │                                 │
                    ↓ HTTPS                           ↓ DNS Queries
            ┌──────────────────┐            ┌──────────────────┐
            │  Traefik         │            │  ExternalDNS     │
            │  (LoadBalancer)  │            │  (Route53)       │
            └────────┬─────────┘            └────────┬─────────┘
                     │                               │
         ┌───────────┼─────────────┐                │
         │           │             │                │
         ↓           ↓             ↓                ↓
    ┌─────────┐ ┌────────┐ ┌──────────┐    ┌────────────────┐
    │Prometheusj │Grafana │ │OpenCost  │    │AWS Route53     │
    └─────────┘ └────────┘ └──────────┘    │(DNS Records)   │
        ↑                                   └────────────────┘
        │ Scraped by
        ├─→ mysql-exporter
        ├─→ mongodb-exporter
        └─→ node-exporter
    
    ┌──────────────────────┐     ┌─────────────────────┐
    │  Karpenter           │     │  ESO + SecretStore  │
    │  (Auto-scaling)      │     │  (Secret Mgmt)      │
    └──────────────────────┘     └─────────────────────┘
         ↓                              ↓
    EC2 Instances (Spot)      ← Synced from AWS Secrets Manager
    
    ┌──────────────────────┐     ┌──────────────────┐
    │  Goldilocks          │     │  VPA Recommender │
    │  (Right-sizing)      │     │  (Usage Analysis)│
    └──────────────────────┘     └──────────────────┘
```

---

## 🔧 Configuration Files Location

```
helm/robot-shop/
├── values.yaml                    ← Main values file
├── values-dev.yaml               ← Development overrides
├── values-prod.yaml              ← Production overrides
├── CHARTS-DOCUMENTATION/
│   ├── 01-KUBE-PROMETHEUS-STACK.md
│   ├── 02-PROMETHEUS-EXPORTERS.md
│   ├── 03-TRAEFIK.md
│   ├── 04-EXTERNAL-SECRETS-OPERATOR.md
│   ├── 05-EXTERNAL-DNS.md
│   ├── 06-KARPENTER.md
│   ├── 07-OPENCOST.md
│   └── 08-GOLDILOCKS.md
├── templates/
│   ├── prometheus/
│   ├── grafana/
│   └── ... (other resources)
└── Chart.yaml

charts/
├── edns/
│   ├── EDNS-IAM.tf              ← External DNS IAM
│   └── iam_eso.json             ← IAM policy JSON
├── eso/
│   ├── ESO-IAM.tf               ← External Secrets Operator IAM
│   ├── SecretStore.yaml         ← Kubernetes SecretStore CRD
│   ├── db-external-secret.yaml  ← Database secrets
│   └── iam_eso.json
├── karpenter/
│   ├── EC2NodeClass.yaml        ← Node configuration
│   ├── NodePool.yaml            ← Scaling rules
│   ├── karpenter-IAM.tf         ← IAM setup
│   ├── EKS-NodeGroups.tf        ← System node group
│   ├── iam-karpenter.json
│   └── sqs-queue.tf             ← Spot interruption queue
└── opencost/
    └── opencost.tf              ← S3 bucket for spot pricing
```

---

## 🎯 Deployment Strategy

### Phase 1: Monitoring Stack (Day 1)
```
1. Deploy Traefik (ingress base)
2. Deploy Prometheus + Grafana
3. Deploy MySQL/MongoDB exporters
4. Access Grafana dashboard
✓ Goal: Visibility into cluster state
```

### Phase 2: Secret Management (Day 1-2)
```
1. Set up AWS Secrets Manager
2. Deploy External Secrets Operator
3. Create ExternalSecret resources
4. Verify secrets auto-sync
✓ Goal: No secrets in Git
```

### Phase 3: DNS & Certificate Management (Day 2)
```
1. Deploy External DNS
2. Deploy Let's Encrypt resolver in Traefik
3. Create Ingress for monitoring stack
4. Verify DNS records created
5. Verify certificates issued
✓ Goal: Automatic DNS + TLS
```

### Phase 4: Cost Optimization (Day 3)
```
1. Deploy Karpenter
2. Deploy OpenCost
3. Deploy Goldilocks
4. Let VPA collect data (7 days)
5. Start optimizing workloads
✓ Goal: Cost reduction visibility
```

---

## 📈 Typical Cost Breakdown

```
Component                 Monthly Cost    Savings with Setup
────────────────────────────────────────────────────────────
Traefik LoadBalancer           $20        N/A
Karpenter (node scaling)        $0        40% on EC2 costs
OpenCost (monitoring)           $0        Visibility = savings
Goldilocks (right-sizing)       $0        30-50% on resource waste
ESO + Secrets Manager          $5        Convenience + security
External DNS (Route53)          $0        Automation
Prometheus Storage             $50        Could reduce with retention
────────────────────────────────────────────────────────────
Total Setup Cost              $75        Typical Savings: 40-60%
```

---

## 🐛 Common Issues & Solutions

### Issue: "Pod pending, can't scale"
**Solution**: Check Karpenter logs
```bash
kubectl logs -l app.kubernetes.io/name=karpenter -n karpenter | tail -50
```

### Issue: "DNS not resolving"
**Solution**: Verify ExternalDNS created records
```bash
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

### Issue: "Secrets not syncing"
**Solution**: Check ESO pod logs
```bash
kubectl logs -l app.kubernetes.io/name=external-secrets -n robot-shop
```

### Issue: "Certificate not issued"
**Solution**: Check Traefik pod logs
```bash
kubectl logs -l app.kubernetes.io/name=traefik -n kube-system
```

---

## 🔐 Security Checklist

- [ ] **No secrets in values.yaml** (use ExternalSecrets)
- [ ] **Enable network policies** (restrict pod communication)
- [ ] **RBAC configured** (least privilege)
- [ ] **TLS everywhere** (HTTPS for all ingress)
- [ ] **Pod security policies** (restrict privileged pods)
- [ ] **Pod Identity** (not static credentials)
- [ ] **Audit logging** (CloudTrail for AWS API calls)
- [ ] **Regular backups** (Prometheus data, configurations)
- [ ] **Secret rotation** (AWS Secrets Manager lifecycle)
- [ ] **Monitoring & alerting** (unusual cost spikes, security events)

---

## 🚨 Monitoring & Alerting Setup

### Critical Alerts to Configure

```yaml
# Prometheus AlertRules:

1. ExporterDown
   expr: up{job="mysql-exporter"} == 0
   for: 5m
   → Database connectivity issue

2. PodMemoryUsageHigh
   expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
   → Pod about to OOMKill

3. NodeDiskPressure
   expr: karpenter_nodes_allocatable - karpenter_nodes_reserved < threshold
   → Node running out of resources

4. CertificateExpiringSoon
   expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
   → Certificate expires in <7 days

5. KarpenterConsolidationFailed
   expr: increase(karpenter_consolidation_errors_total[1h]) > 0
   → Karpenter failing to consolidate nodes
```

---

## 📚 Learning Resources

- **Kubernetes**: https://kubernetes.io/docs/
- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/
- **Traefik**: https://doc.traefik.io/traefik/
- **Karpenter**: https://karpenter.sh/docs/
- **OpenCost**: https://www.opencost.io/docs/
- **Goldilocks**: https://www.fairwinds.com/goldilocks

---

## 🤝 Contributing & Maintaining

### Adding a New Chart

1. Create new markdown file: `NN-CHART-NAME.md`
2. Follow the template structure
3. Include: Overview, Architecture, Config, AWS setup, Troubleshooting
4. Test all examples
5. Add to this index file

### Updating Existing Charts

1. Check chart version changes
2. Update values.yaml examples
3. Test in dev environment first
4. Document breaking changes
5. Update version in documentation

---

## 📝 Documentation Maintenance

- **Review frequency**: Every 3 months
- **Update trigger**: New chart version, new feature, bug fix
- **Last updated**: [Current date]
- **Maintainer**: DevOps Team

---

## 🎓 For New Team Members

**Onboarding Path:**
1. Start with this index (5 min)
2. Read Traefik guide (25 min) - understand ingress
3. Read Kube-Prometheus-Stack guide (30 min) - understand monitoring
4. Read Karpenter guide (60 min) - understand auto-scaling
5. Try deploying to test cluster (2 hours)
6. Read remaining guides based on interest

**Total onboarding time**: ~3.5 hours

---

## 🆘 Support & Escalation

```
Issue Type              Action
────────────────────────────────────────────────────
Pod not starting        → Check pod logs
                        → Check events
                        → Karpenter logs

DNS not resolving       → ExternalDNS logs
                        → Route53 console
                        → Domain settings

Certificate issues      → Traefik logs
                        → Let's Encrypt status
                        → Domain validation

Cost going up           → OpenCost dashboard
                        → Goldilocks recommendations
                        → Karpenter consolidation

Secrets not syncing     → ESO pod logs
                        → AWS credentials
                        → Secret existence
```

---

**Documentation Version**: 1.0  
**Last Updated**: 2026-02-05  
**Next Review**: 2026-05-05
