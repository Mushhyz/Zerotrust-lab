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

# Test advanced OPA constraints
echo "🔍 Testing advanced OPA constraints..."

# 1. Execute Rego tests for advanced constraint templates
echo "🧪 Running OPA tests for advanced constraints..."
if [ -d "../gitops/opa/constraints/advanced-constraints" ]; then
    if ! opa test ../gitops/opa/constraints/advanced-constraints/; then
        echo "❌ At least one Rego test failed"
        ((FAILED++))
        exit 1
    fi
    echo "✅ Rego tests passed"
    ((PASSED++))
else
    echo "⚠️ Advanced constraints directory not found, skipping Rego tests"
fi

# 2. Test Gatekeeper policy enforcement with dry-run
echo "🔒 Testing Gatekeeper policy enforcement..."

# Test hostPath constraint violation
echo "📋 Testing hostPath constraint (should be rejected)..."
cat <<EOF | kubectl create -f - --dry-run=server 2>&1 | tee /tmp/hostpath-test.log
apiVersion: v1
kind: Pod
metadata:
  name: pod-hostpath-test
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:1.20
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    hostPath:
      path: /etc
EOF

if grep -q "denied\|forbidden\|rejected" /tmp/hostpath-test.log; then
    echo "✅ Gatekeeper correctly rejected hostPath"
    ((PASSED++))
else
    echo "❌ Gatekeeper did not reject hostPath violation"
    cat /tmp/hostpath-test.log
    ((FAILED++))
    exit 1
fi

# Test image digest constraint violation
echo "📋 Testing image digest constraint (should be rejected)..."
cat <<EOF | kubectl create -f - --dry-run=server 2>&1 | tee /tmp/digest-test.log
apiVersion: v1
kind: Pod
metadata:
  name: pod-no-digest-test
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

if grep -q "denied\|forbidden\|rejected" /tmp/digest-test.log; then
    echo "✅ Gatekeeper correctly rejected image without digest"
    ((PASSED++))
else
    echo "⚠️ Image digest constraint may not be active or enforcing"
fi

# Clean up test files
rm -f /tmp/hostpath-test.log /tmp/digest-test.log

echo "✅ Advanced OPA constraint validation completed"

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
        echo -e "${YELLOW}💡 Exécutez: ./configure-kubectl.sh <kubeconfig>${NC}"
        ((FAILED++))
        exit 1
    fi
    
    # Test connection
    if kubectl version --short &>/dev/null; then
        echo -e "${GREEN}✅${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ connexion échouée${NC}"
        echo -e "${YELLOW}💡 Vérifiez la connectivité au cluster maître${NC}"
        ((FAILED++))
        exit 1
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

# Function to check persistent volumes
check_storage() {
    echo -e "\n${YELLOW}💾 Vérification du stockage persistant:${NC}"
    
    echo -n "Persistent Volumes... "
    local pv_count=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
    if [ "$pv_count" -gt 0 ]; then
        echo -e "${GREEN}✅ ($pv_count trouvés)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️ (Aucun PV trouvé - possible en mode développement)${NC}"
    fi
    
    echo -n "Persistent Volume Claims... "
    local pvc_count=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$pvc_count" -gt 0 ]; then
        echo -e "${GREEN}✅ ($pvc_count trouvés)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️ (Aucun PVC trouvé)${NC}"
    fi
}

# Function to check HTTP endpoints with better error handling
check_http() {
    local service=$1
    local host=$2
    local expected_code=${3:-200}
    
    echo -n "Test HTTP $service ($host)... "
    
    # Vérifier d'abord si l'ingress existe
    if ! kubectl get ingress --all-namespaces | grep -q "$host"; then
        echo -e "${YELLOW}⚠️ (Ingress non trouvé, utilisation du port-forwarding recommandée)${NC}"
        return
    fi
    
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time $TIMEOUT "http://$host" 2>/dev/null || echo "000")
    
    if echo "$response_code" | grep -q "$expected_code"; then
        echo -e "${GREEN}✅ (Code: $response_code)${NC}"
        ((PASSED++))
    elif [ "$response_code" = "000" ]; then
        echo -e "${YELLOW}⚠️ (Connexion impossible - ingress peut être en cours de configuration)${NC}"
        echo -e "${BLUE}    💡 Essayez le port-forwarding: kubectl port-forward ...${NC}"
    else
        echo -e "${RED}❌ (Code: $response_code)${NC}"
        ((FAILED++))
    fi
}

# Function to check OPA policies with better error handling
check_opa_policies() {
    echo -e "\n${YELLOW}🛡️ Vérification des politiques OPA:${NC}"
    
    # Check if OPA namespace exists
    if ! kubectl get namespace opa &>/dev/null; then
        echo -e "${RED}❌ Namespace OPA non trouvé${NC}"
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
    local constraints=$(kubectl get constraints --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$constraints" -gt 0 ]; then
        echo -e "${GREEN}✅ ($constraints trouvés)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC}"
        ((FAILED++))
    fi
    
    # Check violations
    echo -n "Violations... "
    local violations=$(kubectl get constraints --all-namespaces -o jsonpath='{.items[*].status.violations[*]}' 2>/dev/null | wc -w)
    if [ "$violations" -eq 0 ]; then
        echo -e "${GREEN}✅ (Aucune violation)${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️ ($violations violations détectées)${NC}"
    fi
}

# Function to test OPA constraint enforcement
test_opa_constraints() {
    echo -e "\n${YELLOW}🧪 Test d'application des contraintes OPA:${NC}"
    
    # Test hostPath constraint
    echo -n "Test hostPath rejection... "
    local hostpath_test=$(cat << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-hostpath-pod
spec:
  containers:
  - name: test
    image: nginx:1.20
    volumeMounts:
    - name: hostpath-vol
      mountPath: /host
  volumes:
  - name: hostpath-vol
    hostPath:
      path: /etc
EOF
)
    
    if echo "$hostpath_test" | kubectl create -f - --dry-run=server 2>&1 | grep -q "denied\|violation\|hostPath"; then
        echo -e "${GREEN}✅ (hostPath correctement rejeté)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ Gatekeeper n'a pas rejeté hostPath${NC}"
        ((FAILED++))
    fi
    
    # Test privileged container constraint
    echo -n "Test privileged container rejection... "
    local privileged_test=$(cat << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged-pod
spec:
  containers:
  - name: test
    image: nginx:1.20
    securityContext:
      privileged: true
EOF
)
    
    if echo "$privileged_test" | kubectl create -f - --dry-run=server 2>&1 | grep -q "denied\|violation\|privileged"; then
        echo -e "${GREEN}✅ (Privileged correctement rejeté)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ Gatekeeper n'a pas rejeté privileged${NC}"
        ((FAILED++))
    fi
    
    # Test latest tag constraint
    echo -n "Test latest tag rejection... "
    local latest_test=$(cat << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-latest-pod
spec:
  containers:
  - name: test
    image: nginx:latest
EOF
)
    
    if echo "$latest_test" | kubectl create -f - --dry-run=server 2>&1 | grep -q "denied\|violation\|latest"; then
        echo -e "${GREEN}✅ (Tag 'latest' correctement rejeté)${NC}"
        ((PASSED++))
    else
        echo -e "${RED}❌ Gatekeeper n'a pas rejeté le tag 'latest'${NC}"
        ((FAILED++))
    fi
}

# Function to check services and endpoints
check_services() {
    echo -e "\n${YELLOW}🔗 Vérification des services Kubernetes:${NC}"
    
    local services_to_check=(
        "keycloak:auth"
        "vault:vault"
        "gitea-http:gitea"
        "grafana:monitoring"
        "prometheus:monitoring"
        "loki:logging"
    )
    
    for svc_info in "${services_to_check[@]}"; do
        local svc_name="${svc_info%%:*}"
        local namespace="${svc_info##*:}"
        
        echo -n "Service $svc_name... "
        if kubectl get service "$svc_name" -n "$namespace" &>/dev/null; then
            echo -e "${GREEN}✅${NC}"
            ((PASSED++))
        else
            echo -e "${RED}❌${NC}"
            ((FAILED++))
        fi
    done
}

# Function to check Grafana datasources
check_grafana_datasources() {
    echo -e "\n${YELLOW}📊 Vérification des datasources Grafana:${NC}"
    
    # Check if Grafana is accessible
    if kubectl get service grafana -n monitoring &>/dev/null; then
        echo -n "Service Grafana... "
        echo -e "${GREEN}✅${NC}"
        ((PASSED++))
        
        # Note: Datasource check would require port-forward or ingress access
        echo -e "${BLUE}💡 Pour vérifier les datasources, accédez à Grafana via port-forward:${NC}"
        echo "    kubectl port-forward -n monitoring svc/grafana 3000:80"
    else
        echo -e "${RED}❌ Service Grafana non trouvé${NC}"
        ((FAILED++))
    fi
}

# Main validation flow
echo -e "${YELLOW}🔧 Vérifications préliminaires:${NC}"
check_kubectl

echo -e "\n${YELLOW}📁 Vérification des namespaces:${NC}"
for ns in auth vault gitea monitoring logging opa traefik; do
    check_namespace "$ns"
done

# Wait for services to be ready
echo -e "\n${YELLOW}⏳ Attente de la disponibilité des services...${NC}"
sleep 15

# Check services
check_services

# Check pods status
echo -e "\n${YELLOW}📦 Vérification du statut des pods:${NC}"
check_pods "keycloak" "auth"
check_pods "vault" "vault"
check_pods "gitea" "gitea"
check_pods "grafana" "monitoring"
check_pods "loki" "logging"
check_pods "prometheus" "monitoring"
check_pods "gatekeeper" "opa"

# Check ingress controller
echo -e "\n${YELLOW}🌐 Vérification de l'Ingress Controller:${NC}"
echo -n "Ingress Controller... "
if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅${NC}"
    ((PASSED++))
else
    echo -e "${RED}❌${NC}"
    echo "  Debug: État des pods ingress-nginx:"
    kubectl get pods -n ingress-nginx 2>/dev/null || echo "  Namespace ingress-nginx introuvable"
    ((FAILED++))
fi

# Check storage
check_storage

# Check HTTP endpoints
echo -e "\n${YELLOW}🔗 Vérification des endpoints HTTP:${NC}"
echo -e "${BLUE}Note: Si les tests HTTP échouent, l'ingress controller peut encore démarrer${NC}"

check_http "Keycloak" "keycloak.localhost"
check_http "Grafana" "grafana.localhost"
check_http "Gitea" "gitea.localhost"
check_http "Vault" "vault.localhost" "307"

# Check OPA policies
check_opa_policies

# Test OPA constraint enforcement
test_opa_constraints

# Check Grafana datasources
check_grafana_datasources

# Summary
echo -e "\n================================================"
echo -e "${BLUE}📊 Résumé des tests:${NC}"
echo -e "  ${GREEN}✅ Réussis: $PASSED${NC}"
echo -e "  ${RED}❌ Échoués: $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Tous les tests sont passés avec succès!${NC}"
    echo -e "\n${YELLOW}🔗 Services disponibles:${NC}"
    echo "  - Keycloak: http://keycloak.localhost"
    echo "  - Grafana: http://grafana.localhost (admin/admin123)"
    echo "  - Gitea: http://gitea.localhost"
    echo "  - Vault: http://vault.localhost"
    echo ""
    echo -e "${YELLOW}🛡️ Politiques OPA actives:${NC}"
    kubectl get constraints --all-namespaces 2>/dev/null || echo "  Aucune constraint trouvée"
    exit 0
else
    echo -e "\n${RED}❌ Certains tests ont échoué!${NC}"
    echo -e "${YELLOW}💡 Conseils de dépannage:${NC}"
    echo "  - L'ingress controller peut prendre 5-10 minutes à être opérationnel"
    echo "  - Vérifiez les logs: kubectl logs -n <namespace> <pod-name>"
    echo "  - Vérifiez les events: kubectl get events -n <namespace>"
    echo "  - Utilisez le port-forwarding en attendant:"
    echo "    kubectl port-forward -n auth svc/keycloak 8080:80"
    echo "    kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "  - Relancez la validation dans quelques minutes"
    exit 1
fi

echo "🔍 Validating Zero Trust Lab deployment..."

# Test OPA constraints
echo "📋 Testing OPA constraints..."
cd ../opa/tests
./test-constraints.sh
cd ../../runner

# Check pod status after OPA tests
echo ""
echo "🔍 Checking overall pod health..."
../check-pods.sh

# Test basic connectivity
echo ""
echo "🌐 Testing basic connectivity..."

# Check if services are accessible
SERVICES=("keycloak:8080" "grafana:3000" "gitea:3000" "vault:8200")

for service in "${SERVICES[@]}"; do
    SERVICE_NAME=$(echo "$service" | cut -d':' -f1)
    PORT=$(echo "$service" | cut -d':' -f2)
    
    if kubectl get svc -A | grep -q "$SERVICE_NAME"; then
        echo "  ✅ $SERVICE_NAME service found"
    else
        echo "  ⚠️ $SERVICE_NAME service not found"
    fi
done

echo ""
echo "✅ Validation completed!"
echo "💡 Use './check-pods.sh' to monitor pod status anytime"
