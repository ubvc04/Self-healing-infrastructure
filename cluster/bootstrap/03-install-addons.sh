#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f ../addons/ingress-nginx/namespace.yaml
kubectl apply -f ../addons/ingress-nginx/install.yaml
kubectl apply -f ../addons/storage/local-path-storageclass.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
