redis: #Caches the Git manifests and Kubernetes state so the Repo Server doesn't have to run helm template every single millisecond.
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

# --- 1. REPO SERVER (The Worker) ---
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 3 
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 1Gi 


# --- 2. CONTROLLER (The Brain) ---
controller:
  replicas: 1 
  resources:
    requests:
      cpu: 100m 
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi
  metrics:
    enabled: true 
    serviceMonitor:
      enabled: false 

# --- 3. SERVER (The UI) ---
server:
  replicas: 1
  resources:
    requests:
      cpu: 20m 
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  
  # Run in insecure mode - Traefik handles TLS termination
  insecure: true

  ingress:
    enabled: true
    hostname: argocd.${domain}
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/backend-protocol: "http"
    hosts:
      - host: argocd.${domain}
    # TLS certificate from cert-manager
    tls: true
    extraTls:
      - hosts:
          - argocd.${domain}
        secretName: argocd-tls
    # Backend should use HTTP (port 80), not HTTPS
    https: false

applicationSet:
  replicas: 1
  resources:
    requests:
      cpu: 10m
      memory: 32Mi

configs:
  params:
    server.insecure: true
  cm:
    url: https://argocd.${domain}
  secret:
    argocdServerAdminPassword: "$2a$10$MVBkBkAxErFWaBpXA4Ltz.Kiwhcz0CkNmVZZgZPa/03JpykN50BVO"

notifications:
  enabled: false

global:
  tolerations:
  - key: "workload-type"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"
    
