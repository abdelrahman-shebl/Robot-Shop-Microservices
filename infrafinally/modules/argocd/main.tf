resource "helm_release" "argocd" {
  name       = "argo-cd" # The name of the Helm release
                
  repository = "https://argoproj.github.io/argo-helm" # The URL of the Helm chart repository
  chart      = "argo-cd"
  version = "9.4.1" # The version of the Helm chart to deploy

  namespace  = "argocd" # The Kubernetes namespace where the Helm release will be deployed
  create_namespace = true # Create the namespace if it doesn't exist
  values = [
    templatefile("${path.module}/values/argo-values.tpl", {
      domain = var.domain
    })
  ]
}

resource "" "name" {
  
}


# The `helm_release` resource is used to manage the deployment of a Helm chart in a Kubernetes cluster. In this case, it is deploying the Argo CD application using the specified chart and version. The `values` argument allows you to provide custom values for the Helm chart, which can be templated using the `templatefile` function to inject variables from Terraform. The `depends_on` argument ensures that the Argo CD application is deployed before any dependent resources, such as the Argo CD applications defined in the next resource block.
resource "helm_release" "argocd-apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version = "2.0.4" # The version of the Helm chart to deploy
  disable_openapi_validation = true # Disable OpenAPI validation for the Helm release, which can be useful if the chart includes custom resources that may not be recognized by the Kubernetes API server during deployment.
  depends_on = [ helm_release.argocd ] # Ensure that the Argo CD application is deployed before deploying the Argo CD applications defined in this resource block

  namespace  = "argocd"
  create_namespace = true
  values = [
    templatefile("${path.module}/values/argo-apps-values.tpl", {
      node_role               = var.node_role # The role of the nodes in the Kubernetes cluster where Argo CD will be deployed, which can be used to configure node selectors or tolerations in the Helm chart values.
      env                     = var.env
      domain                  = var.domain
      cluster_name            = var.cluster_name
      region                  = var.region
      cloudIntegrationSecret  = var.cloudIntegrationSecret #kubernetes_secret.opencost_cloud_integration.metadata[0].name
    })
  ]
}

# The `kubernetes_storage_class` resource is used to define a storage class in Kubernetes, which specifies how storage volumes should be provisioned and managed. In this case, it is creating a storage class named "gp3" that uses the AWS EBS CSI driver to provision gp3 volumes. The storage class is set as the default for the cluster, meaning that any PersistentVolumeClaims that do not specify a storage class will use this one by default. The parameters for the storage class specify the type of volume, IOPS, throughput, and encryption settings for the provisioned volumes.
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      # This line makes it the default for the cluster
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  
  storage_provisioner    = "ebs.csi.aws.com" # The provisioner for AWS EBS CSI driver to create gp3 volumes
  reclaim_policy         = "Delete" # The reclaim policy for the storage class, which determines what happens to the underlying storage when a PersistentVolumeClaim is deleted. In this case, it is set to "Delete", meaning that the provisioned volumes will be automatically deleted when the corresponding PersistentVolumeClaims are deleted.
  allow_volume_expansion = true # Allow volumes provisioned with this storage class to be expanded after they have been created, which can be useful for applications that require more storage over time.
  volume_binding_mode    = "WaitForFirstConsumer" # The volume binding mode for the storage class, which determines when the PersistentVolumeClaims will be bound to the provisioned volumes. In this case, it is set to "WaitForFirstConsumer", meaning that the PersistentVolumeClaims will not be bound to any provisioned volumes until a pod that uses the claim is scheduled and starts running. This can help optimize resource usage by ensuring that volumes are only provisioned when they are actually needed.

  parameters = {
    type       = "gp3"
    iops       = "3000" # The IOPS (Input/Output Operations Per Second) for the provisioned gp3 volumes, which can be adjusted based on the performance requirements of the applications using the storage.
    throughput = "125" # The throughput for the provisioned gp3 volumes, which can also be adjusted based on the performance requirements of the applications using the storage.
    encrypted  = "true"
  }
}

# The `terraform_data` resource is used to execute a local script during the destroy phase of the Terraform lifecycle. In this case, it is defined to clean up any orphaned EBS volumes that may be left behind after the EKS cluster and its associated resources are destroyed. The script deletes all PersistentVolumeClaims in the cluster, waits for a short period to allow the EBS CSI driver to detach any volumes, and then uses the AWS CLI to find and delete any EBS volumes that are still in the "available" state and tagged as owned by the cluster. This helps ensure that there are no orphaned resources left in AWS after the cluster is destroyed, which can help prevent unnecessary costs and resource sprawl.
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
