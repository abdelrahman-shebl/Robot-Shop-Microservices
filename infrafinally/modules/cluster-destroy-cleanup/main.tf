############################################
# EBS + PVC + Namespace Cleanup
############################################

resource "terraform_data" "ebs_volume_cleanup" {
  triggers_replace = {
    cluster_name = var.cluster_name
    region       = var.region
  }

  depends_on = var.depends_on_resources

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Step 1: Authenticating..."
      aws eks update-kubeconfig --region ${self.triggers_replace.region} --name ${self.triggers_replace.cluster_name}

      echo "Step 2: Fixing Hanging Namespaces..."
      for ns in $(kubectl get namespaces | grep Terminating | awk '{print $1}'); do
        echo "Force cleaning namespace: $ns"
        kubectl patch namespace $ns -p '{"spec":{"finalizers":null}}' --type=merge || true
      done

      echo "Step 3: Force Deleting PVCs..."
      kubectl delete pvc --all --all-namespaces --ignore-not-found=true --timeout=2m || true

      echo "Step 4: Waiting for detachment..."
      sleep 40

      echo "Step 5: Enhanced EBS Sweep..."
      CLUSTER_NAME="${self.triggers_replace.cluster_name}"

      ALL_VOLS=$(aws ec2 describe-volumes \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
        --query "Volumes[*].VolumeId" --output text)

      KARP_VOLS=$(aws ec2 describe-volumes \
        --filters "Name=tag-key,Values=karpenter.sh/nodepool" \
        --query "Volumes[*].VolumeId" --output text)

      COMBINED_VOLS="$ALL_VOLS $KARP_VOLS"

      for vol in $COMBINED_VOLS; do
        if [ -n "$vol" ] && [ "$vol" != "None" ]; then
          STATE=$(aws ec2 describe-volumes --volume-ids $vol --query "Volumes[0].State" --output text)

          if [ "$STATE" == "in-use" ]; then
            echo "Forcing detachment for $vol"
            aws ec2 detach-volume --volume-id $vol --force || true
            sleep 10
          fi

          echo "Deleting EBS volume: $vol"
          aws ec2 delete-volume --volume-id $vol || true
        fi
      done

      echo "EBS cleanup complete."
    EOT
  }
}

############################################
# LoadBalancer + Ingress Cleanup
############################################

resource "terraform_data" "cleanup_load_balancers" {
  triggers_replace = {
    cluster_name = var.cluster_name
  }

  depends_on = var.depends_on_resources

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Deleting Ingress resources..."
      kubectl delete ingress --all --all-namespaces --ignore-not-found=true --timeout=5m || true

      echo "Deleting LoadBalancer services..."
      kubectl get svc -A | grep LoadBalancer | awk '{print "kubectl delete svc " $2 " -n " $1}' | sh || true

      echo "Waiting 45 seconds for AWS LB controller..."
      sleep 45

      echo "LoadBalancer cleanup complete."
    EOT
  }
}