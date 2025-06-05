#!/bin/bash

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher des messages colorés
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

# Vérification que le script est exécuté en tant qu'utilisateur normal (pas root)
if [[ $EUID -eq 0 ]]; then
   print_error "Ce script ne doit pas être exécuté en tant que root"
   exit 1
fi

print_status "🚀 Installation des prérequis pour Zero Trust Kubernetes Lab sur Ubuntu 22.04"

# Mise à jour du système
print_status "Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# Installation des outils de base
print_status "Installation des outils de base..."
sudo apt install -y curl wget gnupg lsb-release software-properties-common apt-transport-https ca-certificates

# Installation de Docker
print_status "Installation de Docker..."
if ! command -v docker &> /dev/null; then
    # Ajout de la clé GPG officielle de Docker
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Ajout du dépôt Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Installation de Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Ajout de l'utilisateur au groupe docker
    sudo usermod -aG docker $USER
    
    print_success "Docker installé avec succès"
else
    print_success "Docker est déjà installé"
fi

# Installation de kubectl
print_status "Installation de kubectl..."
if ! command -v kubectl &> /dev/null; then
    # Téléchargement de la dernière version stable
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    
    # Installation
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    
    print_success "kubectl ${KUBECTL_VERSION} installé avec succès"
else
    print_success "kubectl est déjà installé"
fi

# Installation de Helm
print_status "Installation de Helm..."
if ! command -v helm &> /dev/null; then
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt update
    sudo apt install -y helm
    
    print_success "Helm installé avec succès"
else
    print_success "Helm est déjà installé"
fi

# Installation de Terraform
print_status "Installation de Terraform..."
if ! command -v terraform &> /dev/null; then
    # Ajout de la clé GPG de HashiCorp
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
    
    # Ajout du dépôt HashiCorp
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    # Installation de Terraform
    sudo apt update
    sudo apt install -y terraform
    
    print_success "Terraform installé avec succès"
else
    print_success "Terraform est déjà installé"
fi

# Installation de kind (Kubernetes in Docker) pour cluster local
print_status "Installation de kind (Kubernetes in Docker)..."
if ! command -v kind &> /dev/null; then
    # Téléchargement de la dernière version de kind
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    
    print_success "kind installé avec succès"
else
    print_success "kind est déjà installé"
fi

# Installation d'outils supplémentaires utiles
print_status "Installation d'outils supplémentaires..."
sudo apt install -y jq git make

# Installation de yq séparément
print_status "Installation de yq..."
if ! command -v yq &> /dev/null; then
    # Essayer avec snap d'abord
    if command -v snap &> /dev/null; then
        if sudo snap install yq 2>/dev/null; then
            print_success "yq installé via snap"
        else
            # Installation manuelle si snap échoue
            print_status "Installation manuelle de yq..."
            YQ_VERSION="v4.40.5"
            wget -qO /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
            print_success "yq ${YQ_VERSION} installé manuellement"
        fi
    else
        # Installation manuelle si snap n'est pas disponible
        print_status "Installation manuelle de yq (snap non disponible)..."
        YQ_VERSION="v4.40.5"
        wget -qO /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
        chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/local/bin/yq
        print_success "yq ${YQ_VERSION} installé manuellement"
    fi
else
    print_success "yq est déjà installé"
fi

# Création d'un cluster Kubernetes local avec kind
print_status "Création d'un cluster Kubernetes local avec kind..."
if ! kind get clusters | grep -q "kind"; then
    # Configuration du cluster kind avec ingress
    cat <<EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
    
    kind create cluster --config=/tmp/kind-config.yaml
    rm /tmp/kind-config.yaml
    
    print_success "Cluster Kubernetes créé avec succès"
else
    print_success "Cluster Kubernetes déjà existant"
fi

# Vérification et correction de la configuration kubectl
print_status "Configuration de kubectl..."
mkdir -p ~/.kube
if kind export kubeconfig --name=kind > /dev/null 2>&1; then
    chmod 600 ~/.kube/config
    print_success "Configuration kubectl mise à jour"
else
    print_warning "Tentative de récupération de la configuration existante..."
    kind export kubeconfig --name=kind 2>/dev/null || true
    if [ -f ~/.kube/config ]; then
        chmod 600 ~/.kube/config
    fi
fi

# Attendre que le cluster soit prêt
print_status "Attente que le cluster soit complètement prêt..."
timeout 120 bash -c 'until kubectl get nodes 2>/dev/null | grep -q "Ready"; do 
    echo "  Attente que le nœud soit prêt..."
    sleep 10
done' || print_warning "Timeout - le cluster peut encore démarrer"

# Installation de NGINX Ingress Controller
print_status "Installation de NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Attendre que le deployment soit créé (sans timeout strict)
print_status "Attente de la création du deployment ingress..."
for i in {1..12}; do
    if kubectl get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
        break
    fi
    echo "  Tentative $i/12 - Attente du deployment..."
    sleep 10
done

# Vérifier l'état sans timeout strict
print_status "Vérification de l'état de l'ingress controller..."
echo "  Pods ingress-nginx actuels:"
kubectl get pods -n ingress-nginx 2>/dev/null || echo "  Namespace en cours de création..."

# Attendre quelques secondes pour que le controller démarre
print_status "Attente du démarrage initial (30 secondes)..."
sleep 30

# Vérifier l'état final
if kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q "Running"; then
    print_success "✅ Ingress controller en cours d'exécution"
else
    print_warning "⚠️ L'ingress controller démarre encore (c'est normal)"
    print_status "État actuel:"
    kubectl get pods -n ingress-nginx 2>/dev/null || echo "  Pods encore en cours de création"
fi

# Vérification des versions installées
print_status "Vérification des versions installées..."
echo ""
print_success "✅ Versions installées :"
echo -e "${GREEN}Docker:${NC} $(docker --version)"
echo -e "${GREEN}kubectl:${NC} $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo -e "${GREEN}Helm:${NC} $(helm version --short)"
echo -e "${GREEN}Terraform:${NC} $(terraform version | head -1)"
echo -e "${GREEN}kind:${NC} $(kind version)"
echo -e "${GREEN}Git:${NC} $(git --version)"
echo -e "${GREEN}Make:${NC} $(make --version | head -1)"
echo -e "${GREEN}jq:${NC} $(jq --version)"
if command -v yq &> /dev/null; then
    echo -e "${GREEN}yq:${NC} $(yq --version)"
else
    echo -e "${YELLOW}yq:${NC} Non installé"
fi

# Vérification de l'accès au cluster
print_status "Vérification de l'accès au cluster Kubernetes..."
if kubectl cluster-info &> /dev/null; then
    print_success "✅ Accès au cluster Kubernetes configuré"
    kubectl get nodes
    
    # Vérification supplémentaire des pods système
    print_status "État des pods système:"
    kubectl get pods -n kube-system --no-headers 2>/dev/null | head -3 || true
    print_status "État des pods ingress:"
    kubectl get pods -n ingress-nginx --no-headers 2>/dev/null || echo "  Ingress controller encore en démarrage"
else
    print_error "❌ Problème d'accès au cluster Kubernetes"
    print_status "Tentative de correction..."
    
    # Réessayer la configuration kubectl
    kind export kubeconfig --name=kind 2>/dev/null || true
    
    if kubectl cluster-info &> /dev/null; then
        print_success "✅ Accès au cluster Kubernetes corrigé"
        kubectl get nodes
    else
        print_error "❌ Impossible de configurer l'accès au cluster"
        print_status "Vérifications à effectuer :"
        print_status "  - Vérifiez que Docker fonctionne: docker ps"
        print_status "  - Vérifiez les clusters kind: kind get clusters"
        print_status "  - Réinitialisez kubectl: kind export kubeconfig"
        print_status "  - Utilisez le script de correction: ./fix-kubectl.sh"
        exit 1
    fi
fi

# Instructions post-installation
echo ""
print_success "🎉 Installation terminée avec succès !"
echo ""
print_warning "⚠️  IMPORTANT : Vous devez vous déconnecter et vous reconnecter (ou redémarrer) pour que les permissions Docker prennent effet."
echo ""
print_status "📋 Résumé de l'installation :"
echo "   • Docker Engine installé et configuré"
echo "   • kubectl installé et configuré"
echo "   • Helm installé"
echo "   • Terraform installé"
echo "   • kind installé"
echo "   • Cluster Kubernetes local créé"
echo "   • NGINX Ingress Controller installé (peut encore démarrer)"
echo "   • Outils supplémentaires : git, make, jq, yq"
echo ""
print_status "🚀 Étapes suivantes :"
echo "   make validate-cluster  # Vérifier l'état du cluster"
echo "   make deploy           # Déployer l'environnement"
echo ""
print_status "🔧 Si vous rencontrez des problèmes :"
echo "   ./fix-kubectl.sh      # Corriger la configuration kubectl"
echo ""
print_status "🔍 Vérifier l'état actuel :"
echo "   kubectl get nodes"
echo "   kubectl get pods --all-namespaces"
