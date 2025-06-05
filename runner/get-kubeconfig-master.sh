#!/bin/bash

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

KUBE_MASTER_IP="${1:-192.168.1.53}"
MASTER_USER="${2:-admin}"

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

print_status "📥 Récupération de la configuration Kubernetes depuis le maître"
print_status "🖥️  Maître: $MASTER_USER@$KUBE_MASTER_IP"

# Vérifier la connectivité SSH
print_status "Test de connectivité SSH..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$MASTER_USER@$KUBE_MASTER_IP" exit 2>/dev/null; then
    print_error "Impossible de se connecter en SSH à $MASTER_USER@$KUBE_MASTER_IP"
    print_status "Solutions possibles :"
    print_status "1. Configurez l'authentification par clé SSH :"
    print_status "   ssh-keygen -t rsa -b 4096"
    print_status "   ssh-copy-id $MASTER_USER@$KUBE_MASTER_IP"
    print_status "2. Ou utilisez le mot de passe :"
    print_status "   $0 $KUBE_MASTER_IP $MASTER_USER --use-password"
    exit 1
fi

print_success "Connexion SSH OK"

# Créer le répertoire .kube si nécessaire
mkdir -p ~/.kube

# Détecter l'emplacement du kubeconfig sur le maître
print_status "Détection de l'emplacement du kubeconfig..."
KUBECONFIG_LOCATIONS=(
    "/etc/kubernetes/admin.conf"
    "~/.kube/config"
    "/home/$MASTER_USER/.kube/config"
    "/root/.kube/config"
)

FOUND_KUBECONFIG=""
for location in "${KUBECONFIG_LOCATIONS[@]}"; do
    if ssh "$MASTER_USER@$KUBE_MASTER_IP" "test -f $location" 2>/dev/null; then
        FOUND_KUBECONFIG="$location"
        print_success "Kubeconfig trouvé: $location"
        break
    fi
done

if [[ -z "$FOUND_KUBECONFIG" ]]; then
    print_error "Aucun fichier kubeconfig trouvé sur le maître"
    print_status "Emplacements vérifiés:"
    for location in "${KUBECONFIG_LOCATIONS[@]}"; do
        print_status "  - $location"
    done
    print_status ""
    print_status "Solutions possibles:"
    print_status "1. Installer Kubernetes sur le maître"
    print_status "2. Vérifier que l'utilisateur $MASTER_USER a accès au kubeconfig"
    print_status "3. Créer un kubeconfig personnalisé"
    exit 1
fi

# Option pour utiliser le mot de passe
if [[ "$3" == "--use-password" ]]; then
    print_status "Récupération avec authentification par mot de passe..."
    scp "$MASTER_USER@$KUBE_MASTER_IP:$FOUND_KUBECONFIG" ~/.kube/config-master
else
    print_status "Récupération de la configuration admin..."
    scp "$MASTER_USER@$KUBE_MASTER_IP:$FOUND_KUBECONFIG" ~/.kube/config-master
fi

if [[ ! -f ~/.kube/config-master ]]; then
    print_error "Échec de la récupération du fichier kubeconfig"
    exit 1
fi

# Modifier l'IP du serveur dans le kubeconfig
print_status "Modification de l'adresse du serveur..."
sed -i "s/server: https:\/\/.*:6443/server: https:\/\/$KUBE_MASTER_IP:6443/g" ~/.kube/config-master

# Copier comme configuration principale
cp ~/.kube/config-master ~/.kube/config
chmod 600 ~/.kube/config

print_success "Configuration kubeconfig récupérée et configurée"

# Tester la connexion
print_status "Test de la connexion au cluster..."
if kubectl cluster-info &>/dev/null; then
    print_success "✅ Connexion au cluster réussie"
    echo ""
    print_status "📊 Informations du cluster :"
    kubectl cluster-info
    echo ""
    print_status "📋 Nœuds disponibles :"
    kubectl get nodes
    echo ""
    print_status "📦 Namespaces existants :"
    kubectl get namespaces
else
    print_error "❌ Impossible de se connecter au cluster"
    print_status "Vérifiez :"
    print_status "1. Que l'API Kubernetes est accessible sur le port 6443"
    print_status "2. Que les certificats sont valides"
    print_status "3. Le contenu de ~/.kube/config"
    exit 1
fi

print_success "🎉 Configuration terminée avec succès !"
print_status "Vous pouvez maintenant utiliser kubectl et déployer l'environnement Zero Trust"
