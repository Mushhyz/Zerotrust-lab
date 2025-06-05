#!/bin/bash

set -e

echo "🚀 Deploying OPA Gatekeeper only..."

# Create namespace
kubectl create namespace opa --dry-run=client -o yaml | kubectl apply -f -

# Deploy Gatekeeper
echo "📦 Installing Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm upgrade --install gatekeeper gatekeeper/gatekeeper \
    --namespace opa \
    --version 3.14.0 \
    --values ../gitops/apps/opa/values.yaml \
    --timeout 10m \
    --wait=false

echo "🔍 Vérification Gatekeeper..."
kubectl wait --for=condition=Available deployment/gatekeeper-controller-manager -n opa --timeout=300s || echo "⚠️ Timeout Gatekeeper, on continue…"

# Check if Gatekeeper is ready
if ! kubectl get deployment/gatekeeper-controller-manager -n opa | grep "1/1"; then
  echo "⚠️ Gatekeeper n'est pas entièrement Ready, poursuite du déploiement en mode non bloquant."
fi

echo "⏳ Waiting for Gatekeeper CRDs to be ready..."
sleep 30

# Deploy constraint templates
echo "📋 Deploying constraint templates..."
for template in constraints/constrainttemplate-*.yaml; do
    if [ -f "$template" ]; then
        echo "  - Applying $(basename $template)"
        kubectl apply -f "$template" || echo "⚠️ Failed to apply $template, continuing..."
    fi
done

echo "⏳ Waiting for constraint templates to be processed..."
sleep 60

# Deploy constraints  
echo "🔒 Deploying constraints..."
for constraint in constraints/constraint-*.yaml; do
    if [ -f "$constraint" ]; then
        echo "  - Applying $(basename $constraint)"
        kubectl apply -f "$constraint" || echo "⚠️ Failed to apply $constraint, continuing..."
    fi
done

echo "✅ OPA Gatekeeper deployment completed!"
echo "🔍 Use 'kubectl get pods -n opa' to check status"
