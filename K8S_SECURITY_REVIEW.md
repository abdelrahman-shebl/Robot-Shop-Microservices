# Kubernetes SecurityContext Review vs Docker Compose

## Summary
Review of securityContext configurations in K8s manifests and verification against docker-compose setup.

---

## ✅ APPLICATION DEPLOYMENTS (UID 1000, GID 2000)

### Configured with SecurityContext

| Service | K8s File | Pod User | RunAsUser | RunAsGroup | fsGroup | Status |
|---------|----------|----------|-----------|-----------|---------|--------|
| **user** | user/deployment.yaml | appuser | 1000 | 2000 | 3000 | ✅ Configured |
| **web** | web/deployment.yaml | appuser | 1000 | 2000 | 3000 | ✅ Configured |
| **ratings** | ratings/deployment.yaml | appuser | 1000 | 2000 | 3000 | ✅ Configured |
| **dispatch** | dispatch/deployment.yaml | appuser | 1000 | 2000 | 3000 | ✅ Configured |

### Missing SecurityContext (Need Update)

| Service | K8s File | Current Status | Action |
|---------|----------|---|---------|
| **cart** | cart/deployment.yaml | ❌ No securityContext | **NEEDS UPDATE** |
| **catalogue** | catalogue/deployment.yaml | ❌ No securityContext | **NEEDS UPDATE** |
| **payment** | payment/deployment.yaml | ❌ No securityContext | **NEEDS UPDATE** |
| **shipping** | shipping/deployment.yaml | ❌ No securityContext | **NEEDS UPDATE** |

---

## 🗄️ DATABASE DEPLOYMENTS

### MySQL StatefulSet (UID 999, GID 999)
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 999        # ✅ Correct (MySQL default)
  runAsGroup: 999       # ✅ Correct
  fsGroup: 999          # ✅ Correct
```
**Status**: ✅ Correct configuration  
**Note**: Aligns with official MySQL image (UID 999)

### MongoDB StatefulSet
```yaml
# ❌ NO securityContext defined
```
**Status**: ⚠️ Missing securityContext  
**Recommendation**: Add UID 999 / GID 999

### Redis StatefulSet (UID 999, GID 999)
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 999        # ✅ Correct (Redis default)
  runAsGroup: 999       # ✅ Correct
  fsGroup: 999          # ✅ Correct
```
**Status**: ✅ Correct configuration  
**Note**: Aligns with official Redis image (UID 999)

---

## 📋 DOCKER-COMPOSE VERIFICATION

### Current Docker Compose Configuration
- **No user restrictions** - Docker Compose does not enforce securityContext
- **Services run as their image default** 
  - Application containers: root (then switch to appuser in Dockerfile)
  - Database containers: Their respective users (mysql/mongo/redis)

### Alignment Check

| Service | Docker Compose User | K8s RunAsUser | Dockerfile User | Match Status |
|---------|---|---|---|---|
| user | root → appuser | 1000 | appuser (1000) | ✅ Match |
| web | root → appuser | 1000 | appuser (1000) | ✅ Match |
| ratings | root → appuser | 1000 | appuser (1000) | ✅ Match |
| dispatch | root → appuser | 1000 | appuser (1000) | ✅ Match |
| cart | root → appuser | **Missing** | appuser (1000) | ⚠️ Inconsistent |
| catalogue | root → appuser | **Missing** | appuser (1000) | ⚠️ Inconsistent |
| payment | root → appuser | **Missing** | appuser (1000) | ⚠️ Inconsistent |
| shipping | root → appuser | **Missing** | appuser (1000) | ⚠️ Inconsistent |
| mysql | root → mysql (999) | 999 | mysql (999) | ✅ Match |
| mongodb | root → mongodb (999) | **Missing** | mongodb (999) | ⚠️ Missing in K8s |
| redis | root → redis (999) | 999 | redis (999) | ✅ Match |

---

## Issues Found

### Critical Issues

1. **Missing SecurityContext in Application Deployments**
   - cart, catalogue, payment, shipping deployments lack securityContext
   - These applications have UID 1000 in Dockerfiles but no K8s enforcement
   - **Risk**: Containers could potentially run as root in K8s

2. **Missing SecurityContext in MongoDB**
   - No securityContext in mongodb/statefulset.yaml
   - MongoDB Dockerfile doesn't enforce user switch
   - **Risk**: MongoDB runs as root or uncontrolled user

### Configuration Inconsistencies

| Issue | Details | Impact |
|-------|---------|--------|
| **Incomplete Security** | Some services have securityContext, others don't | Inconsistent security posture |
| **Database Security** | MongoDB lacks both Dockerfile USER and K8s securityContext | High risk |
| **Container Escape** | Missing `seccompProfile: RuntimeDefault` in some deployments | Medium risk |
| **Privilege Escalation** | Not all containers have `allowPrivilegeEscalation: false` | Medium risk |

---

## Docker-Compose Issues

### Problems with Current Setup

1. **No User Enforcement** - Docker Compose doesn't enforce securityContext equivalent
2. **Works by Convention** - Relies on Dockerfile `USER` directive
3. **Root Execution Risk** - Before `USER` switch, all RUN commands execute as root
4. **Inconsistent with K8s** - Docker Compose can't replicate K8s security restrictions

### Example: Current Flow
```
Docker Compose:
1. Start container (root)
2. Execute entrypoint (root initially)
3. Dockerfile USER appuser (1000)
4. App runs as appuser

K8s without securityContext:
1. Pod starts with image default
2. If no USER in Dockerfile: runs as root
3. If USER in Dockerfile: runs as appuser (but K8s doesn't enforce)

K8s with securityContext (UID 1000):
1. Pod forcibly runs as UID 1000
2. Even if Dockerfile says USER root, K8s overrides
3. Guaranteed non-root execution
```

---

## Recommendations

### Immediate Actions Required

#### 1. Add SecurityContext to Application Deployments
```yaml
# Add to: cart, catalogue, payment, shipping deployments
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 2000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: service
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true  # Optional but recommended
      capabilities:
        drop:
          - ALL
```

#### 2. Add SecurityContext to MongoDB StatefulSet
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    fsGroup: 999
    seccompProfile:
      type: RuntimeDefault
  
  containers:
  - name: mongo
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
```

#### 3. Add USER Directive to MongoDB Dockerfile
```dockerfile
FROM mongo:6.0

# ... setup ...

# Ensure MongoDB runs as non-root
USER mongodb  # Already default, but make explicit
```

#### 4. Add Capabilities to Ratings (PHP/Apache)
```yaml
# Already has:
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    add:
      - NET_BIND_SERVICE  # Required for Apache to bind to port 80
```
**Note**: This is correct - Apache needs NET_BIND_SERVICE to run on port 80 as non-root

#### 5. Consider readOnlyRootFilesystem for Stateless Services
```yaml
# For: dispatch, catalogue (if stateless)
securityContext:
  readOnlyRootFilesystem: true
# Create emptyDir for any needed writable paths:
volumes:
- name: tmp
  emptyDir: {}
```

---

## Verification Checklist

- [ ] All application deployments have securityContext
- [ ] All database statefulsets have securityContext
- [ ] UIDs match between Dockerfile and K8s manifest
- [ ] GIDs match between Dockerfile and K8s manifest
- [ ] fsGroup set correctly for file permission inheritance
- [ ] `allowPrivilegeEscalation: false` on all containers
- [ ] `capabilities: drop: [ALL]` on containers not needing elevated privileges
- [ ] `seccompProfile: type: RuntimeDefault` on all pods
- [ ] readOnlyRootFilesystem where applicable (with emptyDir for temp files)

---

## Testing Commands

### Docker Compose Verification
```bash
# Check if services start correctly
docker-compose up -d
docker-compose exec user id          # Should show uid=1000
docker-compose exec cart id          # Should show uid=1000
docker-compose exec mysql id         # Should show uid=999
docker-compose exec mongodb id       # Should show uid=999
docker-compose down
```

### Kubernetes Verification
```bash
# Apply manifests
kubectl apply -f K8s/

# Check running user
kubectl exec -it deployment/user -- id           # uid=1000
kubectl exec -it deployment/cart -- id           # uid=1000
kubectl exec -it statefulset/mysql-ss-0 -- id   # uid=999
kubectl exec -it statefulset/mongo-ss-0 -- id   # uid=999

# Check security context enforcement
kubectl describe pod <pod-name> | grep -A 10 securityContext
```

---

## Summary Table

### Current State
```
Deployments with SecurityContext:      4/8 (50%) ❌
StatefulSets with SecurityContext:    2/3 (67%) ⚠️
Dockerfiles with USER directive:      11/12 (92%) ✅
Docker Compose Enforcement:           None (relies on Dockerfile) ⚠️
K8s/Docker Alignment:                 Partial ⚠️
```

### After Recommendations
```
Deployments with SecurityContext:      8/8 (100%) ✅
StatefulSets with SecurityContext:    3/3 (100%) ✅
Dockerfiles with USER directive:      12/12 (100%) ✅
Docker Compose Enforcement:           Aligned via Dockerfile ✅
K8s/Docker Alignment:                 Full ✅
```
