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
    maxReplicas: 3 # Allow it to burst if you deploy everything at once
  resources:
    requests:
      # Needs a little CPU to process Helm charts
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 1Gi # Give it headroom for large charts


# --- 2. CONTROLLER (The Brain) ---
controller:
  replicas: 1 # You rarely need 2 for small clusters
  resources:
    requests:
      # Very efficient, mostly just watches the API
      cpu: 50m 
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  # Good metrics for debugging, keeps resource cost low
  metrics:
    enabled: true 
    serviceMonitor:
      enabled: false # Turn off unless you actually have Prometheus running

# --- 3. SERVER (The UI) ---
server:
  replicas: 1
  resources:
    requests:
      # Sits idle most of the time
      cpu: 20m 
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  
  # KEEP YOUR INGRESS CONFIG
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
    hosts:
      - host: argocd.shebl.com

    tls:
      - secretName: argocd-tls
        hosts:
          - argocd.shebl.com

# Keep ApplicationSet, it's tiny and useful
applicationSet:
  replicas: 1
  resources:
    requests:
      cpu: 10m
      memory: 32Mi

configs:
  secret:
    argocdServerAdminPassword: "$2a$10$MVBkBkAxErFWaBpXA4Ltz.Kiwhcz0CkNmVZZgZPa/03JpykN50BVO"

notifications:
  enabled: false

  
