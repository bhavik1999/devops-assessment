#!/bin/bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD server..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=300s

echo "==> Installing ArgoCD CLI..."
curl -sSL -o /tmp/argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd

echo "==> Applying app-of-apps..."
kubectl apply -f ../gitops/infrastructure/argocd/app-of-apps.yaml

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "==="
echo "ArgoCD Admin Password: $ARGOCD_PASS"
echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then open: https://localhost:8080"
echo "==="
