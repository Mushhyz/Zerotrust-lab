#!/bin/bash

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration du cluster maître
KUBE_MASTER_IP="192.168.1.53"
KUBE_MASTER_PORT="6443"
RUNNER_USER=${RUNNER_USER:-"runner"}

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

# Vérification des paramètres
if [[ $# -gt 0 ]]; then
    KUBE_MASTER_IP="$1"
fi

if [[ $# -gt 1 ]]; then
    KUBE_MASTER_PORT="$2"
fi

print_status "🚀 Configuration du runner pour cluster Kubernetes distant"
print_status "📡 Maître Kubernetes: $KUBE_MASTER_IP:$KUBE_MASTER_PORT"
print_status "👤 Utilisateur runner: $RUNNER_USER"

# Vérification que le script n'est pas exécuté en tant que root
if [[ $EUID -eq 0 ]]; then
    print_warning "Script exécuté en tant que root - configuration pour l'utilisateur $RUNNER_USER"
    if [[ -z "$SUDO_USER" && -z "$RUNNER_USER" ]]; then
        print_error "Impossible de déterminer l'utilisateur cible"
        print_status "Utilisez: sudo -u <utilisateur> ./setup-runner.sh"
        exit 1
    fi
    TARGET_USER="${SUDO_USER:-$RUNNER_USER}"
    TARGET_HOME="/home/$TARGET_USER"
else
    TARGET_USER="$USER"
    TARGET_HOME="$HOME"
fi

print_status "Configuration pour l'utilisateur: $TARGET_USER"

# Mise à jour du système
print_status "Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# Installation des outils de base
print_status "Installation des outils de base..."
sudo apt install -y curl wget gnupg lsb-release software-properties-common apt-transport-https ca-certificates

# Installation de Docker (optionnel pour certains outils)
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
    sudo usermod -aG docker $TARGET_USER
    
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

# Installation d'outils supplémentaires
print_status "Installation d'outils supplémentaires..."
sudo apt install -y jq git make openssh-client

# Installation de yq
print_status "Installation de yq..."
if ! command -v yq &> /dev/null; then
    if command -v snap &> /dev/null; then
        if sudo snap install yq 2>/dev/null; then
            print_success "yq installé via snap"
        else
            YQ_VERSION="v4.40.5"
            wget -qO /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
            chmod +x /tmp/yq
            sudo mv /tmp/yq /usr/local/bin/yq
            print_success "yq ${YQ_VERSION} installé manuellement"
        fi
    else
        YQ_VERSION="v4.40.5"
        wget -qO /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
        chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/local/bin/yq
        print_success "yq ${YQ_VERSION} installé manuellement"
    fi
else
    print_success "yq est déjà installé"
fi

# Test de connectivité au cluster maître
print_status "Test de connectivité au cluster maître..."
if ping -c 3 "$KUBE_MASTER_IP" &> /dev/null; then
    print_success "Connectivité réseau OK vers $KUBE_MASTER_IP"
else
    print_warning "Impossible de joindre $KUBE_MASTER_IP"
    print_status "Vérifiez la connectivité réseau et les règles de pare-feu"
fi

# Test du port Kubernetes API
print_status "Test du port Kubernetes API..."
if timeout 5 bash -c "</dev/tcp/$KUBE_MASTER_IP/$KUBE_MASTER_PORT" 2>/dev/null; then
    print_success "Port $KUBE_MASTER_PORT accessible sur $KUBE_MASTER_IP"
else
    print_warning "Port $KUBE_MASTER_PORT non accessible sur $KUBE_MASTER_IP"
    print_status "Vérifiez que l'API Kubernetes est démarrée et accessible"
fi

# Configuration du répertoire .kube
print_status "Configuration du répertoire .kube..."
if [[ $EUID -eq 0 ]]; then
    sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.kube"
    # Créer un fichier de configuration exemple
    cat > /tmp/kubeconfig-template << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTi... # À remplacer par le vrai certificat
    server: https://$KUBE_MASTER_IP:$KUBE_MASTER_PORT
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: runner-user
  name: runner-context
current-context: runner-context
users:
- name: runner-user
  user:
    client-certificate-data: LS0tLS1CRUdJTi... # À remplacer par le vrai certificat
    client-key-data: LS0tLS1CRUdJTi...         # À remplacer par la vraie clé
EOF
    
    sudo cp /tmp/kubeconfig-template "$TARGET_HOME/.kube/config-template"
    sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.kube/config-template"
    sudo chmod 600 "$TARGET_HOME/.kube/config-template"
    rm /tmp/kubeconfig-template
else
    mkdir -p "$TARGET_HOME/.kube"
    cat > "$TARGET_HOME/.kube/config-template" << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTi... # À remplacer par le vrai certificat
    server: https://$KUBE_MASTER_IP:$KUBE_MASTER_PORT
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: runner-user
  name: runner-context
current-context: runner-context
users:
- name: runner-user
  user:
    client-certificate-data: LS0tLS1CRUdJTi... # À remplacer par le vrai certificat
    client-key-data: LS0tLS1CRUdJTi...         # À remplacer par la vraie clé
EOF
    chmod 600 "$TARGET_HOME/.kube/config-template"
fi

# Création du script de configuration finale
print_status "Création du script de configuration kubectl..."
cat > /tmp/configure-kubectl.sh << 'EOF'
#!/bin/bash

# Script de configuration kubectl pour le runner
# Usage: ./configure-kubectl.sh <kubeconfig-from-master>

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $# -eq 0 ]]; then
    echo -e "${YELLOW}Usage: $0 <chemin-vers-kubeconfig>${NC}"
    echo -e "${YELLOW}Ou copier le kubeconfig dans ~/.kube/config${NC}"
    exit 1
fi

KUBECONFIG_SOURCE="$1"

if [[ ! -f "$KUBECONFIG_SOURCE" ]]; then
    echo -e "${RED}Fichier kubeconfig non trouvé: $KUBECONFIG_SOURCE${NC}"
    exit 1
fi

# Copier la configuration
cp "$KUBECONFIG_SOURCE" ~/.kube/config
chmod 600 ~/.kube/config

echo -e "${GREEN}Configuration kubectl copiée${NC}"

# Tester la connexion
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Connexion au cluster réussie${NC}"
    kubectl get nodes
else
    echo -e "${RED}❌ Impossible de se connecter au cluster${NC}"
    echo -e "${YELLOW}Vérifiez la configuration dans ~/.kube/config${NC}"
fi
EOF

chmod +x /tmp/configure-kubectl.sh
if [[ $EUID -eq 0 ]]; then
    sudo mv /tmp/configure-kubectl.sh "$TARGET_HOME/configure-kubectl.sh"
    sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/configure-kubectl.sh"
else
    mv /tmp/configure-kubectl.sh "$TARGET_HOME/configure-kubectl.sh"
fi

# Création du script de validation
print_status "Création du script de validation..."
cat > /tmp/validate-runner.sh << 'EOF'
#!/bin/bash

# Script de validation du runner
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🔍 Validation de la configuration du runner${NC}"

# Vérifier les outils
tools=("kubectl" "helm" "terraform" "docker" "git" "jq" "yq")
for tool in "${tools[@]}"; do
    if command -v "$tool" &>/dev/null; then
        echo -e "${GREEN}✅ $tool installé${NC}"
    else
        echo -e "${RED}❌ $tool manquant${NC}"
    fi
done

# Vérifier kubectl
if [[ -f ~/.kube/config ]]; then
    echo -e "${GREEN}✅ Configuration kubectl présente${NC}"
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}✅ Connexion cluster OK${NC}"
        kubectl get nodes --no-headers | head -3
    else
        echo -e "${RED}❌ Connexion cluster échoue${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ Configuration kubectl manquante${NC}"
    echo -e "${YELLOW}Utilisez: ./configure-kubectl.sh <kubeconfig>${NC}"
fi
EOF

chmod +x /tmp/validate-runner.sh
if [[ $EUID -eq 0 ]]; then
    sudo mv /tmp/validate-runner.sh "$TARGET_HOME/validate-runner.sh"
    sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/validate-runner.sh"
else
    mv /tmp/validate-runner.sh "$TARGET_HOME/validate-runner.sh"
fi

# Vérification des versions installées
print_status "Vérification des versions installées..."
echo ""
print_success "✅ Versions installées :"
echo -e "${GREEN}Docker:${NC} $(docker --version 2>/dev/null || echo 'Non installé')"
echo -e "${GREEN}kubectl:${NC} $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || echo 'Non installé')"
echo -e "${GREEN}Helm:${NC} $(helm version --short 2>/dev/null || echo 'Non installé')"
echo -e "${GREEN}Terraform:${NC} $(terraform version 2>/dev/null | head -1 || echo 'Non installé')"
echo -e "${GREEN}Git:${NC} $(git --version 2>/dev/null || echo 'Non installé')"
echo -e "${GREEN}jq:${NC} $(jq --version 2>/dev/null || echo 'Non installé')"
echo -e "${GREEN}yq:${NC} $(yq --version 2>/dev/null || echo 'Non installé')"

# Instructions finales
echo ""
print_success "🎉 Configuration du runner terminée avec succès !"
echo ""
print_status "📋 Étapes suivantes :"
echo "1. 📥 Récupérez le fichier kubeconfig du maître:"
echo "   scp admin@$KUBE_MASTER_IP:/etc/kubernetes/admin.conf ~/kubeconfig"
echo ""
echo "2. 🔧 Configurez kubectl:"
echo "   ./configure-kubectl.sh ~/kubeconfig"
echo ""
echo "3. 🔍 Validez la configuration:"
echo "   ./validate-runner.sh"
echo ""
echo "4. 🚀 Déployez l'environnement Zero Trust:"
echo "   make deploy"
echo ""
print_warning "⚠️  Note importante :"
print_warning "Vous devez obtenir un fichier kubeconfig valide du maître Kubernetes"
print_warning "pour que le runner puisse se connecter au cluster."
echo ""
print_status "🔐 Pour créer un utilisateur runner sur le maître :"
echo "kubectl create serviceaccount runner-sa"
echo "kubectl create clusterrolebinding runner-binding --clusterrole=cluster-admin --serviceaccount=default:runner-sa"
echo "kubectl create token runner-sa"
