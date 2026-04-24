#!/bin/bash
set -euo pipefail

echo "==> Installing k3s..."
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb

echo "==> Setting KUBECONFIG..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

echo "==> Waiting for node to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=120s

echo "==> Applying namespaces..."
kubectl apply -f ../gitops/infrastructure/namespaces/namespaces.yaml

echo "==> k3s setup complete!"
kubectl get nodes
