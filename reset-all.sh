#!/bin/bash

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fonction pour supprimer les releases Helm avec timeout
cleanup_helm_releases() {
    print_status "🧹 Suppression des releases Helm..."
    
    local releases_info=(
        "keycloak:auth"
        "vault:vault"
        "gitea:gitea"
        "gatekeeper:opa"
        "prometheus:monitoring"
        "grafana:monitoring"
        "loki:logging"
    )
    
    for release_info in "${releases_info[@]}"; do
        local release="${release_info%%:*}"
        local namespace="${release_info##*:}"
        
        if helm list -n "$namespace" 2>/dev/null | grep -q "$release"; then
            print_status "Suppression de la release $release dans $namespace"
            timeout 90 helm uninstall "$release" -n "$namespace" --ignore-not-found || {
                print_warning "Timeout pour $release, suppression forcée..."
                kubectl delete all,pvc,secret,configmap -l app.kubernetes.io/instance="$release" -n "$namespace" --ignore-not-found --grace-period=0 --force || true
            }
        else
            print_status "Release $release déjà supprimée ou inexistante"
        fi
    done
    
    # Attente supplémentaire pour la suppression
    print_status "Attente de la suppression des ressources Helm..."
    sleep 15
}

# Fonction pour supprimer les namespaces avec suppression forcée
cleanup_namespaces() {
    print_status "🗑️ Suppression des namespaces Kubernetes..."
    
    local namespaces=(auth vault gitea opa monitoring logging)
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            print_status "Suppression du namespace $ns"
            
            # Suppression gracieuse d'abord
            kubectl delete namespace "$ns" --ignore-not-found &
            local delete_pid=$!
            
            # Attendre 30 secondes maximum
            if ! timeout 30 wait $delete_pid 2>/dev/null; then
                print_warning "Timeout pour $ns, suppression forcée..."
                
                # Suppression forcée des finalizers
                kubectl get namespace "$ns" -o json 2>/dev/null | \
                    jq '.spec.finalizers = []' | \
                    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - || true
                
                # Forcer la suppression
                kubectl delete namespace "$ns" --grace-period=0 --force --ignore-not-found || true
            fi
        fi
    done
}

# Fonction pour nettoyer les CRDs de Gatekeeper
cleanup_gatekeeper_crds() {
    print_status "🛡️ Nettoyage des CRDs Gatekeeper..."
    
    # Supprimer les constraints d'abord
    kubectl delete constraints --all --ignore-not-found || true
    
    # Supprimer les constraint templates
    kubectl delete constrainttemplates --all --ignore-not-found || true
    
    # Supprimer les CRDs de gatekeeper
    kubectl get crd | grep gatekeeper | awk '{print $1}' | xargs -r kubectl delete crd --ignore-not-found || true
}

# Fonction pour nettoyer les webhooks
cleanup_webhooks() {
    print_status "🔗 Nettoyage des webhooks..."
    
    # Supprimer les validating admission webhooks
    kubectl delete validatingadmissionwebhooks --all --ignore-not-found || true
    
    # Supprimer les mutating admission webhooks  
    kubectl delete mutatingadmissionwebhooks --all --ignore-not-found || true
}

print_status "🧹 Démarrage de la réinitialisation complète..."

# Vérification préalable
if ! kubectl cluster-info &>/dev/null; then
    print_warning "Cluster Kubernetes non accessible, nettoyage local uniquement"
    if [ -d "terraform" ]; then
        cd terraform
        rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup 2>/dev/null || true
        cd ..
    fi
    print_success "Nettoyage local terminé"
    exit 0
fi

# Destruction des ressources Terraform
print_status "🧹 Destruction des ressources Terraform..."
if [ -d "terraform" ]; then
    cd terraform
    if [ -f ".terraform.lock.hcl" ]; then
        timeout 300 terraform destroy -auto-approve || {
            print_warning "Timeout Terraform destroy, nettoyage manuel..."
        }
    else
        print_warning "Terraform non initialisé, passage au nettoyage manuel"
    fi
    cd ..
else
    print_warning "Répertoire terraform non trouvé"
fi

# Nettoyage des releases Helm
cleanup_helm_releases

# Nettoyage des CRDs et webhooks avant les namespaces
cleanup_gatekeeper_crds
cleanup_webhooks

# Nettoyage des namespaces
cleanup_namespaces

# Attendre que tout soit supprimé
print_status "⏳ Attente de la suppression complète..."
for i in {1..30}; do
    remaining=$(kubectl get namespaces auth vault gitea opa monitoring logging 2>/dev/null | grep -v "STATUS" | wc -l)
    if [ "$remaining" -eq 0 ]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Vérification finale
remaining_ns=$(kubectl get namespaces auth vault gitea opa monitoring logging 2>/dev/null | grep -v "STATUS" | wc -l)
if [ "$remaining_ns" -gt 0 ]; then
    print_warning "Certains namespaces existent encore:"
    kubectl get namespaces auth vault gitea opa monitoring logging 2>/dev/null || true
    print_status "Cela peut être normal si certains ont des finalizers"
else
    print_success "Tous les namespaces ont été supprimés"
fi

# Nettoyage final des ressources orphelines
print_status "🧹 Nettoyage final des ressources orphelines..."
kubectl delete pv --all --ignore-not-found || true
kubectl delete clusterroles,clusterrolebindings -l app.kubernetes.io/managed-by=Helm --ignore-not-found || true

print_success "✅ Réinitialisation terminée avec succès"
print_status "🚀 Prêt pour un nouveau déploiement:"
print_status "   make deploy"
print_status "💡 Si des ressources persistent, redémarrez le cluster:"
print_status "   make reset-force"
