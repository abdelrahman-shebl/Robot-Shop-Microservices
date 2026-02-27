resource "helm_release" "argocd" {
  name       = "argo-cd"
                
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version = "9.4.1"

  namespace  = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/argo-values.tpl", {
      domain = var.domain
    })
  ]
}

resource "helm_release" "argocd-apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version = "2.0.4"
  disable_openapi_validation = true
  depends_on = [ helm_release.argocd ]

  namespace  = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/argo-apps-values.tpl", {
      node_role               = var.node_role
      env                     = var.env
      domain                  = var.domain
      cluster_name            = var.cluster_name
      region                  = var.region
      cloudIntegrationSecret  = var.cloudIntegrationSecret #kubernetes_secret.opencost_cloud_integration.metadata[0].name
    })
  ]
}



resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      # This line makes it the default for the cluster
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type       = "gp3"
    iops       = "3000"
    throughput = "125"
    encrypted  = "true"
  }
}

# INFO: This script is kept as a fallback but should no longer be needed.
# The cascade delete finalizer on each ArgoCD Application now handles PVC/EBS
# cleanup automatically when apps are removed during terraform destroy.
# Uncomment and test if volumes are found orphaned after a destroy.
/*
resource "terraform_data" "cleanup_ebs_volumes" {
  triggers_replace = {
    cluster_name = var.cluster_name
  }

  # Hook runs BEFORE the EKS cluster (and its addons) or StorageClass are destroyed
  depends_on = [
    kubernetes_storage_class.gp3
  ]

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting all PersistentVolumeClaims..."
      kubectl delete pvc --all --all-namespaces --ignore-not-found=true --timeout=5m || true
      
      echo "Waiting 30 seconds for EBS CSI driver to detach volumes..."
      sleep 30
      
      echo "Sweeping AWS for orphaned 'available' EBS volumes..."
      CLUSTER_NAME="${self.triggers_replace.cluster_name}"
      VOLUME_IDS=$(aws ec2 describe-volumes \
        --filters "Name=status,Values=available" "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
        --query "Volumes[*].VolumeId" \
        --output text)
        
      if [ -n "$VOLUME_IDS" ]; then
        for vol in $VOLUME_IDS; do
          echo "Forcefully deleting orphaned volume: $vol"
          aws ec2 delete-volume --volume-id "$vol" || true
        done
      fi
    EOT
  }
}
*/