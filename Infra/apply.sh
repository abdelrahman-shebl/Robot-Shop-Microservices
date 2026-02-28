#!/usr/bin/env bash
set -e

CLUSTER_NAME="first-eks"
REGION="eu-central-1"

echo "===== INIT ====="
terraform init -upgrade

echo "===== STAGE 1: BASE INFRA ====="
terraform apply \
  -target=module.vpc \
  -target=module.eks \
  -auto-approve

echo "Updating kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

echo "Waiting for nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo "===== STAGE 2: AWS PLATFORM INFRA ====="
terraform apply \
  -target=module.karpenter_infra \
  -auto-approve

echo "===== STAGE 3: CLUSTER PLATFORM ====="
terraform apply \
  -target=module.argocd \
  -target=module.karpenter_app \
  -auto-approve

echo "Waiting for ArgoCD..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=600s

echo "Waiting for Argo CRDs..."
until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  echo "Waiting for CRDs..."
  sleep 10
done

echo "===== STAGE 4: APPLICATIONS ====="
terraform apply -auto-approve

echo "===== DONE ====="
