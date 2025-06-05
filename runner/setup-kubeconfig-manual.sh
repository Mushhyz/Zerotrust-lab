#!/bin/bash

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

KUBE_MASTER_IP="${1:-192.168.1.53}"
MASTER_USER="${2:-manager}"

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

print_status "🔧 Configuration manuelle du kubeconfig pour cluster distant"
print_status "🖥️  Maître: $MASTER_USER@$KUBE_MASTER_IP"

# Vérifier la connectivité
print_status "Test de connectivité..."
if ! ping -c 1 "$KUBE_MASTER_IP" &>/dev/null; then
    print_error "Impossible de joindre $KUBE_MASTER_IP"
    exit 1
fi

# Créer le répertoire .kube
mkdir -p ~/.kube

print_status "📋 Étapes pour configurer manuellement le kubeconfig:"
echo ""
echo "1. 🔍 Vérifiez si Kubernetes est installé sur le maître:"
echo "   ssh $MASTER_USER@$KUBE_MASTER_IP 'kubectl version'"
echo ""
echo "2. 📂 Localisez le fichier kubeconfig sur le maître:"
echo "   ssh $MASTER_USER@$KUBE_MASTER_IP 'find / -name \"*.conf\" -path \"*/kubernetes/*\" 2>/dev/null'"
echo "   ssh $MASTER_USER@$KUBE_MASTER_IP 'find /home -name config -path \"*/.kube/*\" 2>/dev/null'"
echo ""
echo "3. 📥 Copiez le kubeconfig (remplacez CHEMIN par le bon chemin):"
echo "   scp $MASTER_USER@$KUBE_MASTER_IP:CHEMIN_VERS_KUBECONFIG ~/.kube/config"
echo ""
echo "4. 🔧 Ou créez un kubeconfig basique manuellement:"

cat > ~/.kube/config-template << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://$KUBE_MASTER_IP:6443
    insecure-skip-tls-verify: true
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: admin
  name: admin@kubernetes
current-context: admin@kubernetes
users:
- name: admin
  user:
    username: admin
    password: VOTRE_PASSWORD_ICI
EOF

print_success "Template kubeconfig créé: ~/.kube/config-template"
echo ""
echo "5. 🔑 Modifiez le template avec vos credentials et renommez-le:"
echo "   cp ~/.kube/config-template ~/.kube/config"
echo "   chmod 600 ~/.kube/config"
echo ""
echo "6. ✅ Testez la connexion:"
echo "   kubectl cluster-info"
echo ""

print_status "🔍 Diagnostic du maître:"
echo "Tentative de connexion SSH et vérification..."

if ssh -o ConnectTimeout=5 "$MASTER_USER@$KUBE_MASTER_IP" 'echo "SSH OK"' 2>/dev/null; then
    print_success "SSH accessible"
    
    print_status "Vérification de Docker sur le maître..."
    if ssh "$MASTER_USER@$KUBE_MASTER_IP" 'docker --version' 2>/dev/null; then
        print_success "Docker installé sur le maître"
    else
        print_warning "Docker non trouvé sur le maître"
    fi
    
    print_status "Vérification de kubectl sur le maître..."
    if ssh "$MASTER_USER@$KUBE_MASTER_IP" 'kubectl version --client' 2>/dev/null; then
        print_success "kubectl installé sur le maître"
    else
        print_warning "kubectl non trouvé sur le maître"
    fi
    
    print_status "Recherche de fichiers kubernetes..."
    ssh "$MASTER_USER@$KUBE_MASTER_IP" 'find /etc -name "*kubernetes*" -type d 2>/dev/null | head -5' || true
    ssh "$MASTER_USER@$KUBE_MASTER_IP" 'find /home -name ".kube" -type d 2>/dev/null | head -5' || true
    
else
    print_error "SSH non accessible - vérifiez les credentials"
    echo ""
    print_status "Solutions SSH:"
    echo "1. Copiez votre clé publique:"
    echo "   ssh-copy-id $MASTER_USER@$KUBE_MASTER_IP"
    echo ""
    echo "2. Ou utilisez le mot de passe directement:"
    echo "   ssh $MASTER_USER@$KUBE_MASTER_IP"
fi

print_status "💡 Si le maître n'a pas de cluster Kubernetes:"
echo "1. Installez un cluster sur le maître:"
echo "   curl -sfL https://get.k3s.io | sh -"
echo ""
echo "2. Ou utilisez un cluster local sur le runner:"
echo "   ./install-prerequisites.sh"
echo "   make deploy"
