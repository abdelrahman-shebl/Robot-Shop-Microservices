# Goldilocks (Fairwinds) - Complete Guide

## Overview

Goldilocks is a tool that analyzes your Kubernetes workloads and recommends optimal resource requests and limits. It uses the Vertical Pod Autoscaler (VPA) under the hood to understand actual usage patterns.

**The problem it solves:**
```
Common Kubernetes challenge:
├─ App owner: "What CPU/memory should I request?"
├─ DevOps: "Just put something reasonable"
├─ Result:
│  ├─ Pod 1: 4 GB limit, uses 100 MB → wastes $$$
│  ├─ Pod 2: 512 MB limit, uses 900 MB → OOMKilled randomly
│  └─ Pod 3: 2 vCPU limit, spikes to 2.5 vCPU → throttled
│
├─ Application owner: "Why is it slow?"
├─ DevOps: "Check the logs"
└─ No data-driven way to right-size workloads

With Goldilocks:
├─ Actual utilization tracked for 30 days
├─ Recommended requests based on usage
├─ Recommended limits based on peaks
├─ "Just right" sizing (not too big, not too small)
└─ Save money while improving reliability!
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Vertical Pod Autoscaler (VPA)                      │
│  ┌──────────────────────────────────────────────────┐
│  │ Recommender:                                      │
│  │ - Watches pod metrics for 1 week                 │
│  │ - Calculates 50th percentile (avg usage)        │
│  │ - Calculates 95th percentile (peak usage)       │
│  │ - Generates recommendations                      │
│  └──────────────────────────────────────────────────┘
│         (Updater disabled - we only want advice!)
│
├─ Goldilocks Controller ─────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐
│  │ Watches Pods                                      │
│  │ ├─ Creates VPA CRD for each pod                 │
│  │ ├─ Reads VPA recommendations                    │
│  │ └─ Stores recommendations                        │
│  └──────────────────────────────────────────────────┘
│
├─ Goldilocks Dashboard ──────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐
│  │ Web UI                                            │
│  │ ├─ Shows current vs recommended resources       │
│  │ ├─ Savings calculation                          │
│  │ └─ One-click recommendations                    │
│  └──────────────────────────────────────────────────┘
│
└──────────────────────────────────────────────────────┘
         ↓ Metrics from
┌──────────────────────────────────────────────────────┐
│  Prometheus / Metrics Server                        │
│  - Pod CPU usage                                    │
│  - Pod memory usage                                 │
│  - Container metrics                                │
└──────────────────────────────────────────────────────┘
```

---

## How Goldilocks Works

### 1. **VPA Creation**

```
Day 1: Goldilocks pod starts
  └─ Finds all pods in cluster
  └─ Creates VPA resource for each pod
  └─ VPA recommender starts watching

Day 1-7: Observation period
  ├─ VPA watches pod metrics
  ├─ Collects: CPU spikes, memory peaks, sustained load
  ├─ Calculates percentiles
  └─ Stores in VPA status

Day 7+: Recommendations available
  ├─ VPA generates recommendations
  ├─ Goldilocks reads VPA status
  ├─ Dashboard displays recommendations
  └─ Team can see "rightsize this pod"
```

### 2. **Recommendation Logic**

```yaml
VPA Analysis:
  ┌─ CPU Usage over 7 days ─────┐
  │ Peak: 1200m                 │
  │ 95th percentile: 900m       │ ← Recommended limit
  │ 50th percentile: 400m       │
  │ Average: 500m               │ ← Recommended request
  │ Min: 10m                    │
  └─────────────────────────────┘

VPA Recommendation:
  request: 500m    # Enough for normal operations
  limit: 1200m     # Handles peak bursts
  
Team decision:
  ├─ Conservative: request: 500m, limit: 1000m
  ├─ Balanced: request: 400m, limit: 800m (cost savings!)
  └─ Aggressive: request: 250m, limit: 500m (risky)
```

---

## Helm Chart Configuration

### 1. **Basic Enable**

```yaml
goldilocks:
  enabled: true
```

---

### 2. **VPA (Vertical Pod Autoscaler)**

```yaml
goldilocks:
  vpa:
    enabled: true
    recommender:
      enabled: true
    updater:
      enabled: false  # CRITICAL: We only want advice, not automatic updates
```

**Why updater must be false:**

```
With updater: enabled (DANGEROUS)
┌─────────────────────────────────────────┐
│ VPA recommends: 500m CPU                │
│                                         │
│ Updater action: Restart pod with 500m  │
│                                         │
│ Issues:                                 │
│ ├─ Pod restarts = downtime              │
│ ├─ Pods restart in waves = cascading   │
│ ├─ No change control                   │
│ ├─ Might break applications             │
│ └─ Team doesn't review changes         │
└─────────────────────────────────────────┘

With updater: disabled (SAFE)
┌─────────────────────────────────────────┐
│ VPA recommends: 500m CPU                │
│                                         │
│ Goldilocks action: Show in dashboard   │
│                                         │
│ Team reviews:                           │
│ ├─ "Does 500m sound right?"             │
│ ├─ Check if application changed         │
│ ├─ Schedule deployment during low-load  │
│ └─ Apply recommendation carefully       │
└─────────────────────────────────────────┘

Recommendation: Always disable updater
Use Goldilocks as advisory tool only
```

---

### 3. **Controller Settings**

```yaml
goldilocks:
  controller:
    flags:
      on-by-default: true
      # ↓ When true: Goldilocks creates VPA for EVERY pod in cluster
      # When false: Only create VPA for explicitly labeled pods
```

**When to use each mode:**

```yaml
# on-by-default: true (Comprehensive monitoring)
# Goldilocks watches: ALL pods
# Use case: Medium/large clusters where you want complete visibility
# Cost: Higher (VPA for every pod)
# Recommendation: Start with this for learning

# on-by-default: false (Selective monitoring)
# Goldilocks watches: Only pods with label goldilocks.fairwinds.com/enabled=true
# Use case: Large clusters (cost control)
# Cost: Lower (only VPA for important pods)
# Recommendation: After learning, move to this for cost/performance
```

**Selective monitoring example:**

```yaml
goldilocks:
  controller:
    flags:
      on-by-default: false
      # Only monitor namespaces explicitly enabled
      include-namespaces: "payment,backend,api-gateway"
      # OR use labels instead:
      # label-key: "goldilocks.fairwinds.com/enabled"
      # label-value: "true"
```

**Pod labeling for selective monitoring:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: payment-processor
  labels:
    goldilocks.fairwinds.com/enabled: "true"  # Goldilocks monitors this
spec:
  containers:
  - name: processor
    image: payment-processor:v1
```

---

### 4. **Dashboard Configuration**

```yaml
goldilocks:
  dashboard:
    enabled: true
    replicaCount: 1          # Number of dashboard replicas
    service:
      type: ClusterIP
      port: 80               # Dashboard service port
    
    # Exclude system pods that shouldn't be optimized
    excludeContainers: "linkerd-proxy,istio-proxy,aws-node,kube-proxy"
    # ↓ These containers are infrastructure, skip recommendations
```

**Container exclusion list:**

```yaml
excludeContainers: >
  linkerd-proxy,
  istio-proxy,
  aws-node,
  kube-proxy,
  calico-node,
  coredns,
  etcd,
  karpenter
  # Add any other system containers that shouldn't be optimized
```

---

### 5. **Ingress Configuration**

```yaml
goldilocks:
  dashboard:
    ingress:
      enabled: true
      ingressClassName: traefik
      annotations:
        traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
      
      hosts:
        - host: goldilocks.shebl.com
          paths:
            - path: /
              type: Prefix
      
      tls:
        - secretName: goldilocks-tls
          hosts:
            - goldilocks.shebl.com
```

---

### 6. **Resource Requests/Limits**

```yaml
goldilocks:
  dashboard:
    resources:
      requests:
        cpu: 50m             # Minimum CPU for dashboard
        memory: 256Mi        # Minimum memory
      limits:
        cpu: 100m            # Maximum CPU
        memory: 512Mi        # Maximum memory
```

**Why dashboard needs resources:**

```
Dashboard responsibilities:
├─ Watch all VPA resources in cluster
├─ Read metrics from Prometheus
├─ Calculate recommendations
├─ Serve web UI (handle requests)
├─ Store recommendation cache
└─ Sync with new pods continuously

If starved on resources:
├─ Dashboard becomes slow
├─ Recommendations update slowly
├─ Web UI loads slow
└─ Not ideal user experience
```

---

## Complete Goldilocks Configuration Example

```yaml
goldilocks:
  enabled: true

  # 1. VPA (The engine)
  vpa:
    enabled: true
    recommender:
      enabled: true
    updater:
      enabled: false  # CRITICAL: Only advisory

  # 2. Controller
  controller:
    flags:
      on-by-default: true  # Or false for selective monitoring
      # For selective: include-namespaces: "payment,backend,api"

  # 3. Dashboard
  dashboard:
    enabled: true
    replicaCount: 1  # 1 for dev, 2+ for HA
    
    service:
      type: ClusterIP
      port: 80
    
    # System containers to exclude
    excludeContainers: "linkerd-proxy,istio-proxy,aws-node,kube-proxy,coredns"
    
    # Ingress setup
    ingress:
      enabled: true
      ingressClassName: traefik
      annotations:
        traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
      
      hosts:
        - host: goldilocks.shebl.com
          paths:
            - path: /
              type: Prefix
      
      tls:
        - secretName: goldilocks-tls
          hosts:
            - goldilocks.shebl.com
    
    # Resource limits
    resources:
      requests:
        cpu: 50m
        memory: 256Mi
      limits:
        cpu: 100m
        memory: 512Mi
```

---

## Using Goldilocks Dashboard

### 1. **Access the Dashboard**

```
Visit: https://goldilocks.shebl.com
(Or http://localhost:8080 if port-forwarding)

Dashboard shows:
├─ All namespaces with recommendations
├─ All pods in each namespace
└─ For each pod: current vs recommended resources
```

### 2. **Understanding Recommendations**

```yaml
Pod: payment-processor
Container: main

Current Settings:
  requests:
    cpu: 2000m      # Requesting 2 cores
    memory: 2Gi     # Requesting 2 GB
  limits:
    cpu: 4000m      # Max 4 cores
    memory: 4Gi     # Max 4 GB

Goldilocks Recommendation:
  Requests should be:
    cpu: 500m       # Actually uses ~400m average
    memory: 512Mi   # Actually uses ~250Mi average
  
  Limits should be:
    cpu: 1000m      # Peak observed: 950m
    memory: 1Gi     # Peak observed: 800Mi

Savings:
  CPU: 2000m → 500m = 75% reduction
  Memory: 2Gi → 512Mi = 75% reduction
  Monthly cost: $50 → $12.50 (saves $37.50!)
```

### 3. **Dashboard Views**

#### Namespace View
```
Shows:
├─ Namespace name
├─ Pod count
├─ Total current requests
├─ Total recommended requests
├─ Potential savings ($)
└─ Individual pod recommendations
```

#### Pod Detail View
```
Shows per container:
├─ Current requests/limits
├─ Recommended requests/limits
├─ Usage history graph
├─ Confidence level (based on data points)
└─ Action buttons: Accept recommendation
```

---

## Interpreting Recommendations

### Confidence Levels

```
Confidence HIGH (1+ week of data):
├─ Based on 7+ days of actual usage
├─ Multiple usage cycles observed
├─ Good sample size
└─ Recommendation is reliable

Confidence MEDIUM (3-7 days):
├─ New pod or recently increased traffic
├─ Some usage patterns observed
├─ Use with caution
└─ Wait a few more days if possible

Confidence LOW (< 3 days):
├─ Very new pod
├─ Not enough data points
├─ Recommendation unreliable
└─ Wait a week before applying
```

### Common Recommendation Patterns

#### Pattern 1: Over-provisioned (Most Common)

```yaml
Current:  requests: 2000m, limits: 4000m
Uses:     ~200m average, ~500m peak
Recommend: requests: 250m, limits: 750m

Action:
├─ Review current settings (probably copy-pasted defaults)
├─ Apply recommendation
├─ Monitor application performance
└─ If good: Save money! If bad: Revert and investigate
```

#### Pattern 2: Barely Provisioned

```yaml
Current:  requests: 500m, limits: 512Mi
Uses:     ~450m average, ~480m peak
Recommend: requests: 500m, limits: 512Mi

Action:
├─ Increase slightly for safety margin
├─ Add 20% buffer: requests: 600m, limits: 600Mi
├─ Application is well-sized already
└─ No cost savings, but ensures reliability
```

#### Pattern 3: Spike Workload

```yaml
Current:  requests: 1000m, limits: 2000m
Pattern:  900m for 23h/day, spikes to 1900m for 1h/day

Recommendation: requests: 500m, limits: 2000m

Action:
├─ Accept request reduction (saves money most of day)
├─ Keep high limit (handles spike)
├─ OR use Horizontal Pod Autoscaler for spikes
└─ Consider cron job scale-up for predictable spikes
```

---

## Right-Sizing Strategy

### Conservative Approach (Maximum Reliability)

```yaml
# Goldilocks recommends: 500m
# Your setting: requests: 500m, limits: 1000m
#              (add 100% buffer for safety)

Pros:
├─ Won't hit limit under unexpected load
├─ Graceful degradation instead of OOMKill
└─ High reliability

Cons:
├─ Higher cost than necessary
└─ Wasted resources
```

### Balanced Approach (Recommended for Production)

```yaml
# Goldilocks recommends: requests 500m, limits 900m
# Your setting: requests: 400m, limits: 800m
#              (reduces by 20% for cost, keeps limits safe)

Pros:
├─ Good cost savings
├─ Reasonable safety margin
└─ Handles most scenarios

Cons:
├─ Slight risk during traffic spikes
└─ Monitor closely after applying
```

### Aggressive Approach (Cost-Focused)

```yaml
# Goldilocks recommends: requests 500m, limits 900m
# Your setting: requests: 250m, limits: 750m
#              (aggressive cost cutting)

Pros:
├─ Maximum cost savings
└─ Forces infrastructure efficiency

Cons:
├─ High risk of OOMKill/throttling
├─ Requires aggressive horizontal scaling
└─ Only for non-critical workloads
```

### Recommendation:

```
Start with: Conservative approach
Monitor for: 2 weeks
Then move to: Balanced approach
If stable: Maintain or go more aggressive for cost
If issues: Keep conservative

Process:
1. Apply recommendation
2. Monitor CPU/memory/error rates
3. If stable for 2 weeks: Cost savings achieved
4. If problems: Revert and investigate root cause
```

---

## Applying Recommendations

### Manual Method (Recommended for review)

```yaml
# Current deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
spec:
  template:
    spec:
      containers:
      - name: main
        image: payment:v1
        resources:
          requests:
            cpu: 2000m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 4Gi

# Update with recommendation:
# From dashboard: requests 500m/512Mi, limits 1000m/1Gi

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
spec:
  template:
    spec:
      containers:
      - name: main
        image: payment:v1
        resources:
          requests:
            cpu: 500m         # ← Updated
            memory: 512Mi     # ← Updated
          limits:
            cpu: 1000m        # ← Updated
            memory: 1Gi       # ← Updated

# Then apply:
kubectl apply -f deployment.yaml

# Monitor:
kubectl top pods -l app=payment-processor
kubectl logs -l app=payment-processor
```

### Advanced: GitOps Workflow

```yaml
# Create a GitHub issue from Goldilocks recommendation
# Use Goldilocks API or webhook

# Example PR comment bot could create:
---
Title: Rightsize payment-processor resources
Body:
Goldilocks recommends:
- CPU request: 500m (was 2000m)
- Memory request: 512Mi (was 2Gi)
- Potential savings: $50/month

Confidence: HIGH (7+ days of data)

Steps:
1. Review recommendation in dashboard
2. Approve and merge
3. Monitor for 1 week
4. Close issue when stable
```

---

## Troubleshooting

### Problem: "No recommendations available"

**Reasons:**
- VPA needs 1 week of data
- Pod was just created
- Pod has been idle

**Solution:**
```bash
# Check VPA status
kubectl describe vpa <pod-name>

# Wait for recommendations:
# Typically available after 7 days

# Check if VPA is actually scraping metrics:
kubectl logs -l app=vpa-recommender
```

### Problem: "Recommendations seem too aggressive"

**Cause:** Short observation period or spike activity

**Solution:**
```yaml
# Use conservative buffer:
# If Goldilocks says 500m, use 750m (50% buffer)

# Or configure VPA percentiles:
# Default: 50th percentile for request, 95th for limit
# Can tune these values in VPA spec
```

### Problem: "Dashboard is slow"

**Solution:**
```yaml
# Increase resources
resources:
  limits:
    memory: 1Gi  # Was 512Mi

# Or reduce pods being monitored:
controller:
  flags:
    on-by-default: false
    include-namespaces: "critical-services-only"
```

---

## Production Checklist

- [ ] VPA installed with recommender enabled
- [ ] Updater disabled (only advisory)
- [ ] Dashboard ingress configured
- [ ] On-by-default set appropriately
- [ ] Waited 1 week for recommendations
- [ ] Reviewed first batch of recommendations
- [ ] Updated 1-2 non-critical pods
- [ ] Monitored for 2 weeks
- [ ] Created cost tracking spreadsheet
- [ ] Documented recommendation process for team
- [ ] Set alerts on OOMKill events (to catch bad right-sizing)
- [ ] Scheduled monthly review of new recommendations

---

## Integration with Other Tools

### With Karpenter (Cost Optimization Loop)

```
Goldilocks → Right-size pods
  ↓
Pods use less CPU/memory
  ↓
Karpenter sees lower resource utilization
  ↓
Karpenter consolidates nodes
  ↓
Cluster shrinks → Lower AWS costs
```

### With OpenCost (Cost Tracking)

```
OpenCost calculates current cost
  ↓
Goldilocks recommends right-sizing
  ↓
Apply recommendations
  ↓
OpenCost shows new, lower cost
  ↓
Measure savings (usually 30-50%)
```

---

## Reference

- [Goldilocks Documentation](https://www.fairwinds.com/goldilocks)
- [GitHub: FairWinds Goldilocks](https://github.com/FairwindsOps/goldilocks)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Kubernetes Resource Requests/Limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
