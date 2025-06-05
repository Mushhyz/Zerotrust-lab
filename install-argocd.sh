#!/bin/bash

set -e

echo "🚀 Installation d'Argo CD..."

# Installation d'Argo CD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Attente du démarrage d'Argo CD..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Récupération du mot de passe admin
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "✅ Argo CD installé avec succès!"
echo "🔗 Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "👤 Login: admin"
echo "🔑 Password: $ARGOCD_PASSWORD"

# Application de l'application root
echo "📦 Déploiement de l'application root..."
kubectl apply -f gitops/base/argo-root-app.yaml

echo "🎯 Argo CD configuré pour GitOps!"
