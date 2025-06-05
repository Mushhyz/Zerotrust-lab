#!/bin/bash

set -e

echo "🛡️ Déploiement de Gatekeeper (OPA) uniquement..."

cd terraform
terraform init

echo "📦 Déploiement de Gatekeeper..."
terraform apply -target=helm_release.opa -auto-approve

echo "⏳ Vérification que Gatekeeper est opérationnel..."
kubectl rollout status deployment/gatekeeper-controller-manager -n opa --timeout=180s
kubectl rollout status deployment/gatekeeper-audit -n opa --timeout=180s

echo "✅ Gatekeeper déployé avec succès!"
kubectl get pods -n opa

echo ""
echo "🛡️ Application des politiques OPA de base..."

# Application des contraintes de base
echo "📋 Application des ConstraintTemplates de base..."
kubectl apply -f ../opa/constraints/constrainttemplate-hostnetwork.yaml
kubectl apply -f ../opa/constraints/constrainttemplate-latest-tag.yaml
kubectl apply -f ../opa/constraints/constrainttemplate-privileged.yaml
kubectl apply -f ../opa/constraints/constrainttemplate-resources.yaml

# Attendre que les CRDs soient prêtes
echo "⏳ Attente que les ConstraintTemplates soient prêtes..."
kubectl wait --for=condition=Established crd/k8spsphostnetwork.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8sdisallowlatesttag.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8spspprivileged.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequiredresources.constraints.gatekeeper.sh --timeout=60s

echo "📋 Application des Constraints de base..."
kubectl apply -f ../opa/constraints/constraint-deny-hostnetwork.yaml
kubectl apply -f ../opa/constraints/constraint-deny-latest-tag.yaml
kubectl apply -f ../opa/constraints/constraint-deny-privileged.yaml
kubectl apply -f ../opa/constraints/constraint-require-resources.yaml

echo ""
echo "🔐 Déploiement des politiques avancées..."

# Vérifier que Gatekeeper est complètement prêt avant d'appliquer les contraintes avancées
echo "⏳ Vérification finale que Gatekeeper est prêt pour les politiques avancées..."
kubectl rollout status deployment/gatekeeper-controller-manager -n opa --timeout=180s
kubectl rollout status deployment/gatekeeper-audit -n opa --timeout=180s

# Attendre que les webhooks soient actifs
echo "⏳ Attente que les admission webhooks soient actifs..."
sleep 30

# Vérifier si le dossier advanced-constraints existe
if [ -d "../gitops/opa/constraints/advanced-constraints" ]; then
    echo "📋 Application des ConstraintTemplates avancées..."
    
    # Application des templates avancés avec gestion d'erreur
    for template_file in ../gitops/opa/constraints/advanced-constraints/*.yaml; do
        if [[ -f "$template_file" && "$(basename "$template_file")" == constrainttemplate-*.yaml ]]; then
            echo "  Applying $(basename "$template_file")..."
            if ! kubectl apply -f "$template_file"; then
                echo "❌ Échec de l'application de $(basename "$template_file")"
                exit 1
            fi
        fi
    done
    
    echo "⏳ Attente que les nouveaux ConstraintTemplates soient établis..."
    sleep 15
    
    # Vérifier que les CRDs avancées sont créées
    echo "🔍 Vérification des CRDs avancées..."
    kubectl wait --for=condition=Established crd/k8spsphostpath.constraints.gatekeeper.sh --timeout=60s || echo "⚠️ CRD hostpath non disponible"
    kubectl wait --for=condition=Established crd/k8srequireseccomp.constraints.gatekeeper.sh --timeout=60s || echo "⚠️ CRD seccomp non disponible"
    kubectl wait --for=condition=Established crd/k8srequireimagedigest.constraints.gatekeeper.sh --timeout=60s || echo "⚠️ CRD image digest non disponible"
    
    echo "📋 Application des Constraints avancées..."
    
    # Application des contraintes avancées avec gestion d'erreur
    for constraint_file in ../gitops/opa/constraints/advanced-constraints/*.yaml; do
        if [[ -f "$constraint_file" && "$(basename "$constraint_file")" == constraint-*.yaml ]]; then
            echo "  Applying $(basename "$constraint_file")..."
            if ! kubectl apply -f "$constraint_file"; then
                echo "❌ Échec de l'application de $(basename "$constraint_file")"
                echo "  Vérifiez que les ConstraintTemplates correspondants sont installés"
                exit 1
            fi
        fi
    done
    
    echo "✅ Politiques avancées appliquées avec succès!"
else
    echo "⚠️ Dossier gitops/opa/constraints/advanced-constraints non trouvé, application des politiques de base uniquement"
fi

echo ""
echo "🔍 Vérification du statut des politiques..."

# Afficher les ConstraintTemplates installées
echo "📋 ConstraintTemplates installées:"
kubectl get constrainttemplate

echo ""
echo "📋 Constraints actives:"
kubectl get constraints --all-namespaces

echo ""
echo "🎉 Déploiement OPA terminé avec succès!"
echo ""
echo "💡 Commandes utiles:"
echo "  - Voir les violations: kubectl describe constraints"
echo "  - Tester une politique: kubectl create -f test-pod.yaml --dry-run=server"
echo "  - Valider le déploiement: make validate"

cd ..
