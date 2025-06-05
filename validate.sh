#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
FAILED=0
PASSED=0
TIMEOUT=30

echo "🔍 Validation du déploiement Zero Trust Lab"
echo "================================================"

# Function to check if kubectl is configured
check_kubectl() {
    echo -n "Configuration kubectl... "
    
    # First check if kubectl exists
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl non installé${NC}"
        ((FAILED++))
        exit 1
    fi
    
    # Check if config file exists
    if [ ! -f ~/.kube/config ]; then
        echo -e "${RED}❌ fichier config manquant${NC}"
        echo -e "${YELLOW}💡 Exécutez: kind export kubeconfig${NC}"
        ((FAILED++))
        
        # Try to fix automatically
        if command -v kind &> /dev/null && kind get clusters | grep -q "kind"; then
            echo -e "${YELLOW}🔧 Tentative de correction automatique...${NC}"
            kind export kubeconfig --name=kind
            chmod 600 ~/.kube/config
            echo -e "${GREEN}✅ Configuration kubectl corrigée${NC}"
            ((PASSED++))
        else
            exit 1
        fi
    else
        # Test connection
        if kubectl version --short &>/dev/null; then
            echo -e "${GREEN}✅${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌ connexion échouée${NC}"
            echo -e "${YELLOW}💡 Tentative de correction...${NC}"
            
            # Try to fix kubectl connection
            if command -v kind &> /dev/null && kind get clusters | grep -q "kind"; then
                kind export kubeconfig --name=kind
                chmod 600 ~/.kube/config
                
                if kubectl version --short &>/dev/null; then
                    echo -e "${GREEN}✅ Connexion corrigée${NC}"
                    ((PASSED++))
                else
                    echo -e "${RED}❌ Impossible de corriger la connexion${NC}"
                    ((FAILED++))
                    exit 1
                fi
            else
                echo -e "${RED}❌ Cluster kind non trouvé${NC}"
                ((FAILED++))
                exit 1
            fi
        fi
    fi
}

# Function to check namespace existence
check_namespace() {
    local namespace=$1
    echo -n "Namespace $namespace... "
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "${GREEN}✅${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC}"
        ((FAILED++))
    fi
}

# Function to check pod status with improved logic
check_pods() {
    local service=$1
    local namespace=$2
    
    echo -n "Vérification des pods $service... "
    
    # Check multiple possible label selectors
    local selectors=(
        "app.kubernetes.io/name=$service"
        "app=$service"
        "app.kubernetes.io/component=$service"
        "app.kubernetes.io/instance=$service"
    )
    
    local found=false
    for selector in "${selectors[@]}"; do
        if kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | grep -q "Running\|Completed"; then
            echo -e "${GREEN}✅${NC}"
            ((PASSED++))
            found=true
            break
        fi
    done
    
    if [ "$found" = false ]; then
        echo -e "${RED}❌${NC}"
        echo "  Debug: Checking all pods in namespace $namespace:"
        kubectl get pods -n "$namespace" --no-headers 2>/dev/null | head -5 || echo "  Namespace not found or empty"
        ((FAILED++))
    fi
}

# Function to check Helm releases
check_helm_releases() {
    echo -e "\n${YELLOW}📦 Vérification des releases Helm:${NC}"
    
    local releases=(
        "keycloak:auth"
        "vault:vault"
        "gitea:gitea"
        "prometheus:monitoring"
        "grafana:monitoring"
        "loki:logging"
        "gatekeeper:opa"
    )
    
    for release_info in "${releases[@]}"; do
        local release="${release_info%%:*}"
        local namespace="${release_info##*:}"
        
        echo -n "Release $release... "
        if helm list -n "$namespace" 2>/dev/null | grep -q "$release.*deployed"; then
            echo -e "${GREEN}✅${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌${NC}"
            local status=$(helm list -n "$namespace" 2>/dev/null | grep "$release" | awk '{print $8}' || echo "not-found")
            echo "    Status: $status"
            ((FAILED++))
        fi
    done
}

# Function to check OPA policies
check_opa_policies() {
    echo -e "\n${YELLOW}🛡️ Vérification des politiques OPA:${NC}"
    
    # Check if OPA namespace exists
    if ! kubectl get namespace opa &>/dev/null; then
        echo -e "${RED}❌ Namespace OPA non trouvé${NC}"
        ((FAILED++))
        return
    fi
    
    # Check Gatekeeper pods
    echo -n "Pods Gatekeeper... "
    if kubectl get pods -n opa --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✅${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC}"
        kubectl get pods -n opa 2>/dev/null || echo "  Aucun pod trouvé"
        ((FAILED++))
        return
    fi
    
    # Check constraint templates
    echo -n "ConstraintTemplates... "
    local templates=$(kubectl get constrainttemplate --no-headers 2>/dev/null | wc -l)
    if [ "$templates" -gt 0 ]; then
        echo -e "${GREEN}✅ ($templates trouvés)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC}"
        ((FAILED++))
    fi
    
    # Check constraints
    echo -n "Constraints... "
    local constraints=$(kubectl get k8spspprivileged,k8spsphostnetwork,k8sdisallowlatesttag,k8srequiredresources,k8spsphostpath,k8srequireseccomp,k8srequireimagedigest --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$constraints" -gt 0 ]; then
        echo -e "${GREEN}✅ ($constraints trouvés)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC}"
        ((FAILED++))
    fi
}

# Main validation flow
echo -e "${YELLOW}🔧 Vérifications préliminaires:${NC}"
check_kubectl

echo -e "\n${YELLOW}📁 Vérification des namespaces:${NC}"
for ns in auth vault gitea monitoring logging opa; do
    check_namespace "$ns"
done

# Check Helm releases
check_helm_releases

# Check pods status
echo -e "\n${YELLOW}📦 Vérification du statut des pods:${NC}"
check_pods "keycloak" "auth"
check_pods "vault" "vault" 
check_pods "gitea" "gitea"
check_pods "grafana" "monitoring"
check_pods "prometheus" "monitoring"
check_pods "loki" "logging"
check_pods "gatekeeper" "opa"

# Check OPA policies
check_opa_policies

# Summary
echo -e "\n================================================"
echo -e "${BLUE}📊 Résumé des tests:${NC}"
echo -e "  ${GREEN}✅ Réussis: $PASSED${NC}"
echo -e "  ${RED}❌ Échoués: $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Tous les tests sont passés avec succès!${NC}"
    echo -e "\n${YELLOW}🔗 Services disponibles:${NC}"
    echo "  - Keycloak: http://keycloak.localhost (admin/admin123)"
    echo "  - Grafana: http://grafana.localhost (admin/admin123)"
    echo "  - Gitea: http://gitea.localhost"
    echo "  - Vault: http://vault.localhost"
    exit 0
else
    echo -e "\n${RED}❌ Certains tests ont échoué!${NC}"
    echo -e "${YELLOW}💡 Solutions recommandées:${NC}"
    echo "  1. Corriger les timeouts Helm: make fix-helm"
    echo "  2. Redéployer les services échoués: make redeploy"
    echo "  3. Réinitialiser complètement: make reset && make deploy"
    exit 1
fi
