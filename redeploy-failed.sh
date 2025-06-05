#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🔄 Redéploiement des services échoués${NC}"
echo "========================================"

# Ensure we're in the project root
if [ ! -d "terraform" ]; then
    echo -e "${RED}❌ Répertoire terraform non trouvé${NC}"
    echo "Assurez-vous d'être dans le répertoire racine du projet"
    exit 1
fi

# Fix Terraform first
echo -e "${BLUE}🔧 Correction de l'environnement Terraform...${NC}"
cd terraform

# Remove corrupted state and lock files
echo "  Nettoyage des fichiers Terraform corrompus..."
rm -f .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
rm -rf .terraform/

# Reinitialize Terraform
echo "  Réinitialisation de Terraform..."
if ! terraform init; then
    echo -e "${RED}❌ Échec de l'initialisation Terraform${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Terraform réinitialisé avec succès${NC}"

# Check which services failed
echo -e "${BLUE}🔍 Identification des ressources échouées...${NC}"

failed_releases=()

# Check Helm releases status
echo "Vérification des releases Helm..."
if ! helm list -n auth 2>/dev/null | grep -q "keycloak.*deployed"; then
    failed_releases+=("helm_release.keycloak")
    echo "  ❌ keycloak (auth)"
fi

if ! helm list -n vault 2>/dev/null | grep -q "vault.*deployed"; then
    failed_releases+=("helm_release.vault")
    echo "  ❌ vault (vault)"
fi

if ! helm list -n gitea 2>/dev/null | grep -q "gitea.*deployed"; then
    failed_releases+=("helm_release.gitea")
    echo "  ❌ gitea (gitea)"
fi

if ! helm list -n monitoring 2>/dev/null | grep -q "prometheus.*deployed"; then
    failed_releases+=("helm_release.prometheus")
    echo "  ❌ prometheus (monitoring)"
fi

if ! helm list -n monitoring 2>/dev/null | grep -q "grafana.*deployed"; then
    failed_releases+=("helm_release.grafana")
    echo "  ❌ grafana (monitoring)"
fi

if ! helm list -n logging 2>/dev/null | grep -q "loki.*deployed"; then
    failed_releases+=("helm_release.loki")
    echo "  ❌ loki (logging)"
fi

if [ ${#failed_releases[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Aucun service échoué détecté${NC}"
    echo -e "${YELLOW}💡 Si vous rencontrez des problèmes, lancez: make validate${NC}"
    cd ..
    exit 0
fi

echo -e "\n${YELLOW}📦 Redéploiement complet avec Terraform...${NC}"

# Deploy everything with Terraform
echo "  Déploiement de toutes les ressources..."
if timeout 1800 terraform apply -auto-approve; then
    echo -e "${GREEN}✅ Redéploiement réussi${NC}"
else
    echo -e "${RED}❌ Échec du redéploiement complet${NC}"
    echo -e "${YELLOW}💡 Tentative de déploiement par étapes...${NC}"
    
    # Try step-by-step deployment
    echo "  Étape 1: Déploiement des namespaces..."
    terraform apply -target=kubernetes_namespace.auth -target=kubernetes_namespace.vault -target=kubernetes_namespace.gitea -target=kubernetes_namespace.monitoring -target=kubernetes_namespace.logging -auto-approve || true
    
    echo "  Étape 2: Déploiement de Gatekeeper..."
    terraform apply -target=helm_release.opa -auto-approve || true
    
    echo "  Étape 3: Attente que Gatekeeper soit prêt..."
    sleep 60
    
    echo "  Étape 4: Déploiement des services principaux..."
    for resource in "${failed_releases[@]}"; do
        echo "    Déploiement de $resource..."
        terraform apply -target="$resource" -auto-approve || {
            echo -e "${YELLOW}⚠️ Échec de $resource, continuons...${NC}"
        }
        sleep 30
    done
    
    echo "  Étape 5: Application complète finale..."
    terraform apply -auto-approve || {
        echo -e "${RED}❌ Échec du déploiement final${NC}"
    }
fi

# Wait for services to be ready
echo -e "\n${YELLOW}⏳ Attente que les services soient prêts...${NC}"
sleep 60

# Final verification
echo -e "\n${YELLOW}🔍 Vérification finale...${NC}"

# Check Helm releases status
echo "État final des releases Helm:"
for ns in auth vault gitea monitoring logging opa; do
    echo -e "${BLUE}Namespace $ns:${NC}"
    helm list -n "$ns" 2>/dev/null || echo "  Aucune release trouvée"
done

# Check pods status
echo -e "\n${YELLOW}📦 État des pods:${NC}"
for ns in auth vault gitea monitoring logging opa; do
    echo -e "${BLUE}Namespace $ns:${NC}"
    kubectl get pods -n "$ns" --no-headers 2>/dev/null | head -3 || echo "  Namespace vide"
done

echo -e "\n${GREEN}🎉 Redéploiement terminé!${NC}"
echo -e "${YELLOW}💡 Lancez maintenant: make validate${NC}"

cd ..
