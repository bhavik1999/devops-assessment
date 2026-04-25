#!/bin/bash
set -euo pipefail

echo "======================================"
echo "🚀 FULL DEVOPS BOOTSTRAP STARTED"
echo "======================================"

########################################
# 1. Install k3s
########################################
echo "==> Installing k3s..."
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

echo "==> Waiting for node..."
kubectl wait --for=condition=Ready node --all --timeout=120s

########################################
# 2. Namespaces
########################################
echo "==> Creating namespaces..."
kubectl apply -f gitops/infrastructure/namespaces/namespaces.yaml

########################################
# 3. Install ArgoCD
########################################
echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD..."
kubectl wait --for=condition=Available deployment/argocd-server \
  -n argocd --timeout=300s

########################################
# 4. Build & import Docker image
########################################
echo "==> Building sample API image..."
docker build -t sample-api:latest ./sample-api/

echo "==> Importing image into k3s..."
docker save sample-api:latest | sudo k3s ctr images import -

########################################
# 5. Apply GitOps (App of Apps)
########################################
echo "==> Applying ArgoCD app-of-apps..."
kubectl apply -f gitops/infrastructure/argocd/app-of-apps.yaml

########################################
# 6. Get ArgoCD password
########################################
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "======================================"
echo "🔐 ArgoCD Access"
echo "======================================"
echo "Username: admin"
echo "Password: $ARGOCD_PASS"
echo ""
echo "Run this in another terminal:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then open: https://localhost:8080"
echo "======================================"

########################################
# 7. Wait for workloads
########################################
echo "==> Waiting for workloads to stabilize..."
sleep 60
kubectl get pods -A

########################################
# 8. Simulate traffic
########################################
echo "==> Starting traffic simulation..."

kubectl port-forward svc/sample-api -n sample-api 8888:80 &
PF_PID=$!
sleep 5

END_TIME=$((SECONDS + 120))

while [ $SECONDS -lt $END_TIME ]; do
  curl -s http://localhost:8888/ > /dev/null
  curl -s http://localhost:8888/health > /dev/null
  curl -s http://localhost:8888/users > /dev/null
  curl -s http://localhost:8888/users/$((RANDOM % 10 + 1)) > /dev/null
  curl -s -X POST http://localhost:8888/orders > /dev/null

  if (( RANDOM % 5 == 0 )); then
    curl -s http://localhost:8888/slow > /dev/null
  fi

  if (( RANDOM % 8 == 0 )); then
    curl -s http://localhost:8888/error > /dev/null || true
  fi

  sleep 0.5
  echo -n "."
done

echo ""
echo "==> Traffic simulation done!"
kill $PF_PID 2>/dev/null

echo "======================================"
echo "✅ SETUP COMPLETE"
echo "Check Grafana → Tempo / Prometheus / Loki"
echo "======================================"