# Traefik Ingress Controller Guide

## Overview

Traefik is a modern ingress controller and reverse proxy that routes HTTP/HTTPS traffic to your applications. It's significantly easier than traditional ingress controllers due to its dynamic configuration and native Let's Encrypt support.

**Key advantages over nginx-ingress:**
- ✅ Native ACME/Let's Encrypt support (auto-renewing certificates)
- ✅ Dynamic routing without reloading
- ✅ Built-in TLS termination with automatic certificate management
- ✅ Dashboard for real-time traffic visualization
- ✅ Middleware support (rate limiting, auth, compression, etc.)
- ✅ Configuration as CRDs (no ConfigMaps needed)
- ✅ Automatic certificate renewal 30 days before expiry

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Internet / Public DNS                │
├──────────────────────────────────────────────────────────┤
│                          ↓ HTTPS:443                      │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Traefik LoadBalancer Service (traefik.yourdomain) │  │
│  │  - Listens on :80 (redirects to :443)              │  │
│  │  - Listens on :443 (TLS termination)               │  │
│  └────────────────────────────────────────────────────┘  │
│                          ↓                                │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Traefik Pod (Ingress Controller)                  │  │
│  │  - Routes traffic based on Ingress rules           │  │
│  │  - Manages Let's Encrypt certificates              │  │
│  │  - Handles middleware (compression, auth, etc.)    │  │
│  └────────────────────────────────────────────────────┘  │
│         ↙        ↓        ↘        ↙                      │
│  ┌──────┐ ┌────────┐ ┌──────┐ ┌────────┐                 │
│  │Prom  │ │Grafana │ │OpenCost│ │Goldilocks│            │
│  └──────┘ └────────┘ └──────┘ └────────┘                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## Core Traefik Values Explanation

### 1. **Global Enable**

```yaml
traefik:
  enabled: true  # Deploy Traefik in the cluster
```

---

### 2. **Port Configuration**

```yaml
traefik:
  ports:
    web:
      redirectTo: websecure
      # ↓ HTTP (port 80) automatically redirects to HTTPS (port 443)
      # User visits: http://prometheus.yourdomain.com
      # Browser receives: 307 redirect to https://prometheus.yourdomain.com
    
    websecure:
      tls:
        enabled: true
        certResolver: letsencrypt
        # ↓ HTTPS (port 443) uses Let's Encrypt certificates
        # Certificates automatically obtained and renewed
```

**Why this setup matters:**

```
Without redirect:
┌─────────────────────┐
│ User visits:        │
│ prometheus.yourdomain.com
│ (no https specified)│
├─────────────────────┤
│ Browser defaults to│
│ http://            │
│ (unencrypted!)     │
└─────────────────────┘

With our redirect:
┌─────────────────────┐
│ User visits:        │
│ prometheus.yourdomain.com
│                     │
├─────────────────────┤
│ Browser defaults to│
│ http://            │
│ Traefik sees HTTP  │
│ Redirects to HTTPS │
│ Secure connection! │
└─────────────────────┘
```

---

### 3. **Service Configuration**

```yaml
traefik:
  service:
    enabled: true
    type: LoadBalancer
    # ↓ AWS creates an AWS Load Balancer (ALB/NLB)
    # This gives you a public IP/DNS entry
```

**Service types explained:**

```yaml
# LoadBalancer (what we use)
type: LoadBalancer
# Creates:
# - AWS Network Load Balancer (NLB)
# - Or Application Load Balancer (ALB)
# - Assigns public IP/DNS
# Cost: Typically $16-32/month

# Alternative: NodePort
type: NodePort
# Exposes on every node's IP
# Access: http://node-ip:31234
# Not suitable for production (ugly URLs)

# Alternative: ClusterIP
type: ClusterIP
# Only accessible within cluster
# Requires separate load balancer setup
```

**Production best practice:**
```yaml
traefik:
  service:
    enabled: true
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      # Or ALB:
      # service.beta.kubernetes.io/aws-load-balancer-type: elb
```

---

### 4. **Certificate Resolver: Let's Encrypt**

```yaml
traefik:
  certificatesResolvers:
    letsencrypt:
      acme:
        email: sheblabdo00@gmail.com
        # ↓ Let's Encrypt sends renewal notifications here
        
        storage: /data/acme.json
        # ↓ Persistent storage for certificates
        # If lost, Traefik requests new certificates (rate limited!)
        
        tlsChallenge: true
        # ↓ Uses TLS-ALPN-01 challenge (port 443)
        # Traefik proves domain ownership via TLS
        # Much faster than HTTP challenge
```

**How Let's Encrypt works:**

```
1. You request: https://prometheus.yourdomain.com
2. Traefik sees this is a new domain
3. Traefik contacts Let's Encrypt:
   "I control prometheus.yourdomain.com, prove it"
4. Let's Encrypt: "Serve this token on port 443"
5. Traefik serves token on port 443
6. Let's Encrypt connects: "I found your token, you own this domain"
7. Let's Encrypt issues certificate
8. Traefik stores in /data/acme.json
9. Traefik renews 30 days before expiry (automatic)
```

**DNS requirement:**
```
Your DNS must point to Traefik's LoadBalancer IP:

DNS Records (in Route53 or your DNS provider):
  prometheus.yourdomain.com  A  <Traefik-LoadBalancer-IP>
  grafana.yourdomain.com     A  <Traefik-LoadBalancer-IP>
  opencost.yourdomain.com    A  <Traefik-LoadBalancer-IP>
```

---

### 5. **Persistent Storage for Certificates**

```yaml
traefik:
  persistence:
    enabled: true
    path: /data              # Where certificates are stored
    size: 128Mi              # Storage size
    # Creates PersistentVolumeClaim for acme.json
```

**Why this matters:**

```yaml
# Without persistence (ephemeral):
Traefik pod crashes
  ↓
Pod restarts
  ↓
No acme.json found
  ↓
Traefik requests new certificates
  ↓
⚠️  Hit Let's Encrypt rate limit!
  ↓
❌ Can't issue new certificates for 1 week

# With persistence:
Traefik pod crashes
  ↓
Pod restarts
  ↓
acme.json restored from PVC
  ↓
Existing certificates loaded
  ↓
✅ No new certificate requests
```

**Production template:**
```yaml
traefik:
  persistence:
    enabled: true
    path: /data
    size: 128Mi
    storageClassName: gp3  # AWS EBS GP3
    # accessMode defaults to ReadWriteOnce (appropriate for this use)
```

---

## How to Add a New Certificate Quickly

### Traditional Approach (nginx-ingress + cert-manager)

```
Steps:
1. Install cert-manager
2. Create ClusterIssuer
3. Create Certificate CRD
4. Create Ingress with annotation referencing Certificate
5. Wait for cert-manager to issue certificate
6. Monitor certificate expiry

Time: ~5 minutes setup, constant monitoring needed
```

### Traefik Approach (Much Faster!)

```
Steps:
1. Add Ingress with annotation
2. Done! Certificate auto-obtained and renewed

Time: Instant (just add annotation)
```

**Example - Adding Prometheus Certificate:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    # ↓ That's it! Traefik handles certificate automatically

spec:
  ingressClassName: traefik
  
  tls:
    - secretName: prometheus-tls
      hosts:
        - prometheus.yourdomain.com
  
  rules:
    - host: prometheus.yourdomain.com
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

**Traefik automatically:**
- Detects the Ingress
- Contacts Let's Encrypt
- Obtains certificate
- Stores in acme.json
- Serves HTTPS
- Renews automatically 30 days before expiry

---

## Ingress Configuration Best Practices

### Required Annotations & IngressClassName

#### IngressClassName
```yaml
spec:
  ingressClassName: traefik
  # ↓ CRITICAL: Tells Kubernetes this ingress is for Traefik
  # Without this, Traefik ignores it
```

#### Certificate Resolution Annotation
```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    # ↓ CRITICAL: Tells Traefik which certificate resolver to use
    # Must match certificatesResolvers name in Traefik config
```

#### Optional Useful Annotations
```yaml
metadata:
  annotations:
    # Middleware for compression
    traefik.ingress.kubernetes.io/router.middlewares: compress@kubernetescrd
    
    # Redirect HTTP to HTTPS (redundant with port redirect, but explicit)
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    
    # Force HTTPS Strict Transport Security
    traefik.ingress.kubernetes.io/router.middlewares: force-https@kubernetescrd
```

---

### Complete Ingress Template for Your Services

```yaml
# For Prometheus
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
  namespace: robot-shop
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
    - secretName: prometheus-tls
      hosts:
        - prometheus.yourdomain.com
  rules:
    - host: prometheus.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: monitor-prometheus
                port:
                  number: 80

# For Grafana
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: robot-shop
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.yourdomain.com
  rules:
    - host: grafana.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: monitor-grafana
                port:
                  number: 80

# For OpenCost
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: opencost
  namespace: robot-shop
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
    - secretName: opencost-tls
      hosts:
        - opencost.yourdomain.com
  rules:
    - host: opencost.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: opencost-ui
                port:
                  number: 8080
```

---

## Certificate Management Deep Dive

### Automatic Renewal

```yaml
Let's Encrypt certificates: 90-day validity

Traefik renewal schedule:
├─ Day 60 or older: Renew (30 days before expiry)
├─ Renewal process is automatic
├─ No restart needed
└─ acme.json updated with new certificate

If renewal fails:
├─ Warning logged
├─ Certificate still valid for 30 more days
├─ Traefik retries
└─ You get email notification (to sheblabdo00@gmail.com)
```

### Certificate Storage Location

```
PersistentVolume (gp3 EBS)
        ↓
acme.json file format:
{
  "letsencrypt": {
    "account": {
      ...account details...
    },
    "certificates": [
      {
        "domain": {
          "main": "prometheus.yourdomain.com"
        },
        "certificate": "-----BEGIN CERTIFICATE-----...",
        "key": "-----BEGIN RSA PRIVATE KEY-----...",
        ...
      }
    ]
  }
}
```

**Backup strategy:**
```bash
# Daily backup of certificates
kubectl exec -it <traefik-pod> -- tar czf acme-backup.tar.gz /data/
kubectl cp <traefik-pod>:/acme-backup.tar.gz ./backups/
```

---

## Configuration Comparison: Traditional vs Traefik

### Traditional Ingress (nginx-ingress + cert-manager)

```yaml
# 1. Install cert-manager separately
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace

# 2. Create ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx

# 3. Create Ingress with annotation
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - prometheus.yourdomain.com
    secretName: prometheus-tls
  rules:
  - host: prometheus.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 80

Complexity: HIGH
Setup time: 20 minutes
Debugging: Complex (cert-manager logs + nginx logs)
```

### Traefik Approach (Integrated!)

```yaml
# 1. Deploy Traefik with Let's Encrypt resolver (already done)
helm install traefik traefik/traefik \
  --values values.yaml

# 2. Create Ingress with one annotation
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - prometheus.yourdomain.com
    secretName: prometheus-tls
  rules:
  - host: prometheus.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 80

Complexity: LOW
Setup time: 2 minutes
Debugging: Single Traefik logs source
```

---

## Advanced Configuration

### Adding Basic Authentication

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-protected
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    traefik.ingress.kubernetes.io/router.middlewares: prometheus-auth@kubernetescrd
spec:
  ingressClassName: traefik
  # ... rules ...
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: prometheus-auth
spec:
  basicAuth:
    secret: prometheus-auth-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: prometheus-auth-secret
type: Opaque
data:
  # htpasswd -c auth admin
  # htpasswd -b auth admin password123
  # base64 encode the file
  users: YWRtaW46JGFwcjEkTVE...
```

### Rate Limiting

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
spec:
  rateLimit:
    average: 100      # 100 requests per second
    burst: 200        # Allow burst up to 200
```

---

## DNS Setup (Critical Step!)

Your certificates will fail if DNS isn't correct. Here's what you need:

### In AWS Route53 (or your DNS provider)

```
Record Type: A
Name: prometheus.yourdomain.com
Value: <Traefik-LoadBalancer-IP>
TTL: 300

Record Type: A
Name: grafana.yourdomain.com
Value: <Traefik-LoadBalancer-IP>
TTL: 300

Record Type: A
Name: opencost.yourdomain.com
Value: <Traefik-LoadBalancer-IP>
TTL: 300

Record Type: A
Name: goldilocks.shebl.com
Value: <Traefik-LoadBalancer-IP>
TTL: 300
```

**How to find Traefik LoadBalancer IP:**
```bash
kubectl get service traefik -n kube-system
# or
kubectl get svc traefik

# Output shows EXTERNAL-IP (the public IP for DNS records)
```

---

## Troubleshooting

### Problem: "Invalid certificate"

**Cause:** DNS not pointing to Traefik
```bash
# Test DNS resolution
nslookup prometheus.yourdomain.com

# Should show: <Traefik-LoadBalancer-IP>
```

**Solution:**
1. Update DNS records to point to Traefik's LoadBalancer IP
2. Wait 5-15 minutes for DNS propagation
3. Restart Traefik pod: `kubectl rollout restart deployment/traefik`

### Problem: "Too many certificates already issued for exact set of domains"

**Cause:** Let's Encrypt rate limit hit
```
Limit: 50 certificates per exact domain per week
```

**Solution:**
- Use staging Let's Encrypt: `staging-letsencrypt` resolver
- Wait 1 week
- Or use existing certificate secret

### Problem: "Certificate not renewing"

**Debug:**
```bash
# Check acme.json
kubectl exec -it <traefik-pod> -- cat /data/acme.json

# Check Traefik logs
kubectl logs -l app.kubernetes.io/name=traefik
```

---

## Production Checklist

- [ ] DNS records point to Traefik LoadBalancer IP
- [ ] Email address in Let's Encrypt resolver is valid
- [ ] Persistence enabled for /data/acme.json
- [ ] Storage class configured (gp3 for AWS)
- [ ] TLS redirect enabled (web → websecure)
- [ ] Test certificate renewal (wait 1 day or check logs)
- [ ] Monitor acme.json storage usage
- [ ] Backup certificates regularly
- [ ] Set up alerts for certificate expiry
- [ ] Test renewal process in staging first

---

## Quick Reference

### Adding a New Service to Traefik

```yaml
# 1. Create Ingress (copy this template)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service
  annotations:
    traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
spec:
  ingressClassName: traefik
  tls:
    - secretName: my-service-tls
      hosts:
        - my-service.yourdomain.com
  rules:
    - host: my-service.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service-svc
                port:
                  number: 8080

# 2. Update DNS in Route53
# my-service.yourdomain.com  A  <Traefik-IP>

# 3. Done! Certificate auto-obtained in ~30 seconds
```

---

## Reference

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [Let's Encrypt](https://letsencrypt.org/)
- [Traefik Kubernetes Ingress](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/)
