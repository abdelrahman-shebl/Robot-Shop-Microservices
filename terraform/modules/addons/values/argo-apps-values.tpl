.repo: &repo_link
  repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
  targetRevision: "feature/pipeline"
  ref: repo

applications:

  # cert-manager - must deploy first for TLS certificates
  cert-manager:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: cert-manager
        repoURL: https://charts.jetstack.io
        targetRevision: "v1.17.1"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/cert-manager-values.yaml
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-5"
    destination:
      namespace: cert-manager
      server: https://kubernetes.default.svc

  # cert-manager manifests (ClusterIssuer + Certificates)
  cert-manager-manifests:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
        - SkipDryRunOnMissingResource=true
    source:
      path: K8s/cert-manager
      repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
      targetRevision: "feature/pipeline"
    destination:
      namespace: cert-manager
      server: https://kubernetes.default.svc
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-4"

  external-secrets-operator:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
    sources:
      - chart: external-secrets
        repoURL: https://charts.external-secrets.io/
        targetRevision: "1.3.2"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/eso-values.yaml
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
    destination:
      namespace: eso
      server: https://kubernetes.default.svc

  external-secrets-manifests:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    source:
      path: K8s/eso
      repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
      targetRevision: "feature/pipeline"
    destination:
      namespace: eso
      server: https://kubernetes.default.svc
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "0"
    

  traefik:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: traefik
        repoURL: https://traefik.github.io/charts
        targetRevision: "39.0.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/traefik-values.yaml

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
    destination:
      namespace: traefik
      server: https://kubernetes.default.svc

  external-dns:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: external-dns
        repoURL: https://kubernetes-sigs.github.io/external-dns/
        targetRevision: "1.20.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/edns-values.yaml
            # "Surgical" Overrides
          parameters:
            - name: "domainFilters[0]"
              value: "${domain}"
            - name: "aws.region"
              value: "${region}"
            - name: "txtOwnerId"
              value: "${cluster_name}"

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
    destination:
      namespace: edns
      server: https://kubernetes.default.svc

  kube-prometheus-stack:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
        - Replace=true
        - SkipDryRunOnMissingResource=true
    sources:
      - chart: kube-prometheus-stack
        repoURL: https://prometheus-community.github.io/helm-charts
        targetRevision: "68.2.2"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/prometheus-values.yaml
            # "Surgical" Overrides
          parameters:
            - name: "prometheus.ingress.hosts[0]"
              value: "prometheus.${domain}"

            - name: "prometheus.prometheusSpec.externalUrl"
              value: "https://prometheus.${domain}"

            - name: "grafana.ingress.hosts[0]"
              value: "grafana.${domain}"

            # TLS hosts for cert-manager
            - name: "prometheus.ingress.tls[0].hosts[0]"
              value: "prometheus.${domain}"
            - name: "grafana.ingress.tls[0].hosts[0]"
              value: "grafana.${domain}"
                                      

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
    destination:
      namespace: monitoring
      server: https://kubernetes.default.svc

  grafana-dashboards:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    source:
      path: K8s/grafana
      repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
      targetRevision: "feature/pipeline"
    destination:
      namespace: monitoring
      server: https://kubernetes.default.svc
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"


  prometheus-mysql-exporter:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: prometheus-mysql-exporter
        repoURL: ghcr.io/prometheus-community/charts
        targetRevision: "2.12.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/prometheus-mysql-values.yaml
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-2"
    destination:
      namespace: robotshop
      server: https://kubernetes.default.svc

  prometheus-mongodb-exporter:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: prometheus-mongodb-exporter
        repoURL: ghcr.io/prometheus-community/charts
        targetRevision: "3.17.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/prometheus-mongo-values.yaml
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-2"
    destination:
      namespace: robotshop
      server: https://kubernetes.default.svc



  defectdojo:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: defectdojo
        repoURL: https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/helm-charts
        targetRevision: "1.9.12"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/defectdojo-values.yaml
            # "Surgical" Overrides
          parameters:
            - name: "host"
              value: "dojo.${domain}"
            

            - name: "siteUrl"
              value: "https://dojo.${domain}"

            - name: "django.ingress.hosts[0]"
              value: "dojo.${domain}"

            # TLS hosts for cert-manager
            - name: "django.ingress.tls[0].hosts[0]"
              value: "dojo.${domain}"
                                      

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
    destination:
      namespace: dojo
      server: https://kubernetes.default.svc



  opencost:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: opencost
        repoURL: https://opencost.github.io/opencost-helm-chart
        targetRevision: "2.5.5"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/opencost-values.yaml
            # "Surgical" Overrides
          parameters:
            - name: "clusterName"
              value: "${cluster_name}"

            - name: "opencost.cloudIntegrationSecret"
              value: "${cloudIntegrationSecret}"
            
            - name: "opencost.ui.ingress.hosts[0].host"
              value: "opencost.${domain}"

            # TLS hosts for cert-manager
            - name: "opencost.ui.ingress.tls[0].hosts[0]"
              value: "opencost.${domain}"

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-2"
    destination:
      namespace: opencost
      server: https://kubernetes.default.svc

  goldilocks:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - chart: goldilocks
        repoURL: https://charts.fairwinds.com/stable
        targetRevision: "10.2.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/goldilocks-values.yaml
            # "Surgical" Overrides
          parameters:
            - name: "clusterName"
              value: "${cluster_name}"
            
            - name: "dashboard.ingress.hosts[0].host"
              value: "goldilocks.${domain}"

            # TLS hosts for cert-manager
            - name: "dashboard.ingress.tls[0].hosts[0]"
              value: "goldilocks.${domain}"

      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-2"
    destination:
      namespace: goldilocks
      server: https://kubernetes.default.svc

  kyverno:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
        - Replace=true
    sources:
      - chart: kyverno
        repoURL: https://kyverno.github.io/kyverno/
        targetRevision: "3.7.0"
        helm:
          valueFiles:
            - $repo/terraform/modules/addons/values/kyverno-values.yaml
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-2"
    destination:
      namespace: kyverno
      server: https://kubernetes.default.svc

  kyverno-manifests:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    source: 
      path: K8s/kyverno
      repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
      targetRevision: "feature/pipeline"
    destination:
      namespace: kyverno
      server: https://kubernetes.default.svc
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "-1"

  robot-shop:
    namespace: argocd
    project: default
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
    sources:
      - path: helm/robot-shop
        repoURL: https://github.com/abdelrahman-shebl/Robot-Shop-Microservices.git
        targetRevision: "feature/pipeline"
        helm:
          valueFiles:
            - $repo/helm/robot-shop/values.yaml
            - $repo/helm/robot-shop/values-${env}.yaml
          parameters:
            - name: "ingress.host"
              value: "${domain}"
      - <<: *repo_link
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "0"
    destination:
      namespace: robotshop
      server: https://kubernetes.default.svc
