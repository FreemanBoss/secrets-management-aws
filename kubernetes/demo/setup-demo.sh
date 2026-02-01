#!/bin/bash
set -euo pipefail

# Deploy demo resources
kubectl apply -f 01-service-account.yaml
kubectl apply -f 02-external-secrets.yaml
kubectl apply -f 03-secrets-store-csi.yaml
kubectl apply -f 04-vault-integration.yaml
kubectl apply -f 05-demo-deployments.yaml

echo "Demo resources deployed"
kubectl get pods -n demo
