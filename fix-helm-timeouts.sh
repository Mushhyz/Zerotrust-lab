#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🔧 Correction des timeouts Helm${NC}"
echo "========================================="

# Function to cleanup failed release
cleanup_failed_release() {
    local release=$1
    local namespace=$2
    
    echo -e "${YELLOW}🧹 Nettoyage de la release échouée: $release${NC}"
    
    # Uninstall if exists
    if helm list -n "$namespace" 2>/dev/null | grep -q "$release"; then
        echo "  Désinstallation de $release..."
        helm uninstall "$release" -n "$namespace" --ignore-not-found || true
    fi
    
    # Force delete resources
    echo "  Suppression forcée des ressources..."
    kubectl delete all,pvc,secret,configmap -l app.kubernetes.io/instance="$release" -n "$namespace" --ignore-not-found --grace-period=0 --force || true
    
    # Wait for cleanup
    sleep 10
}

# Function to redeploy with increased timeout
redeploy_with_timeout() {
    local release=$1
    local chart=$2
    local namespace=$3
    local values_file=$4
    local repo=$5
    
    echo -e "${BLUE}📦 Redéploiement de $release avec timeout étendu${NC}"
    
    # Create namespace if not exists
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy with extended timeout
    helm install "$release" "$repo/$chart" \
        --namespace "$namespace" \
        --values "$values_file" \
        --timeout 15m \
        --wait \
        --wait-for-jobs || {
        echo -e "${RED}❌ Échec du déploiement de $release${NC}"
        return 1
    }
    
    echo -e "${GREEN}✅ $release déployé avec succès${NC}"
}

# Check current status
echo -e "${BLUE}🔍 Vérification de l'état actuel...${NC}"

failed_releases=()
if helm list --all-namespaces --failed 2>/dev/null | grep -q "failed"; then
    echo "  Releases échouées détectées:"
    helm list --all-namespaces --failed 2>/dev/null | tail -n +2 | while read -r line; do
        release=$(echo "$line" | awk '{print $1}')
        namespace=$(echo "$line" | awk '{print $2}')
        echo "    - $release (namespace: $namespace)"
        failed_releases+=("$release:$namespace")
    done
else
    echo "  Aucune release échouée détectée"
fi

# Update Helm repositories
echo -e "${YELLOW}📦 Mise à jour des repositories Helm...${NC}"
helm repo update

# Fix common failed releases
echo -e "${YELLOW}🔧 Correction des releases problématiques...${NC}"

# Define services with their parameters
declare -A services=(
    ["keycloak"]="keycloak:bitnami:auth:terraform/values/keycloak-values.yaml"
    ["vault"]="vault:hashicorp:vault:terraform/values/vault-values.yaml"
    ["gitea"]="gitea:gitea-charts:gitea:terraform/values/gitea-values.yaml"
    ["prometheus"]="kube-prometheus-stack:prometheus-community:monitoring:terraform/values/prometheus-values.yaml"
    ["grafana"]="grafana:grafana:monitoring:terraform/values/grafana-values.yaml"
    ["loki"]="loki:grafana:logging:terraform/values/loki-values.yaml"
)

# Process each service
for service in "${!services[@]}"; do
    IFS=':' read -r chart repo namespace values_file <<< "${services[$service]}"
    
    echo -e "\n${BLUE}🔄 Traitement de $service...${NC}"
    
    # Check if values file exists
    if [ ! -f "$values_file" ]; then
        echo -e "${YELLOW}⚠️ Fichier de valeurs non trouvé: $values_file${NC}"
        continue
    fi
    
    # Check current status
    current_status=$(helm list -n "$namespace" 2>/dev/null | grep "$service" | awk '{print $8}' || echo "not-found")
    
    case "$current_status" in
        "deployed")
            echo -e "${GREEN}✅ $service déjà déployé correctement${NC}"
            ;;
        "failed"|"pending-upgrade"|"pending-install")
            echo -e "${YELLOW}⚠️ $service en état $current_status, correction...${NC}"
            cleanup_failed_release "$service" "$namespace"
            redeploy_with_timeout "$service" "$chart" "$namespace" "$values_file" "$repo"
            ;;
        "not-found")
            echo -e "${BLUE}📦 $service non trouvé, déploiement...${NC}"
            redeploy_with_timeout "$service" "$chart" "$namespace" "$values_file" "$repo"
            ;;
        *)
            echo -e "${YELLOW}⚠️ $service état inconnu: $current_status${NC}"
            ;;
    esac
done

# Final verification
echo -e "\n${YELLOW}🔍 Vérification finale...${NC}"
echo "État des releases Helm:"
helm list --all-namespaces

# Check for any remaining failed releases
if helm list --all-namespaces --failed 2>/dev/null | grep -q "failed"; then
    echo -e "\n${RED}❌ Certaines releases sont encore en échec${NC}"
    helm list --all-namespaces --failed
    echo -e "${YELLOW}💡 Solutions:${NC}"
    echo "  1. Réessayer: make fix-helm"
    echo "  2. Nettoyage complet: make reset && make deploy"
    echo "  3. Déploiement manuel étape par étape"
    exit 1
else
    echo -e "\n${GREEN}✅ Toutes les releases Helm sont maintenant déployées${NC}"
    
    # Wait for pods to be ready
    echo -e "${YELLOW}⏳ Attente que les pods soient prêts...${NC}"
    sleep 30
    
    echo "État des pods par namespace:"
    for ns in auth vault gitea monitoring logging opa; do
        echo -e "${BLUE}Namespace $ns:${NC}"
        kubectl get pods -n "$ns" --no-headers 2>/dev/null | head -3 || echo "  Namespace vide"
    done
    
    echo -e "\n${GREEN}🎉 Correction des timeouts Helm terminée avec succès!${NC}"
    echo -e "${YELLOW}💡 Lancez maintenant: make validate${NC}"
fi
