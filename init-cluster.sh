#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🚀 Initialisation du cluster Kubernetes pour Zero Trust Lab${NC}"
echo "================================================================"

# Vérification des prérequis
echo -e "\n${YELLOW}🔍 Vérification des prérequis...${NC}"

# Vérifier kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl n'est pas installé${NC}"
    exit 1
fi
echo -e "${GREEN}✅ kubectl trouvé${NC}"

# Vérifier helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ helm n'est pas installé${NC}"
    exit 1
fi
echo -e "${GREEN}✅ helm trouvé${NC}"

# Vérifier terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ terraform n'est pas installé${NC}"
    exit 1
fi
echo -e "${GREEN}✅ terraform trouvé${NC}"

# Vérifier la connexion au cluster
echo -e "\n${YELLOW}🔗 Vérification de la connexion au cluster...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Impossible de se connecter au cluster Kubernetes${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Connexion au cluster OK${NC}"

# Vérifier si NGINX Ingress Controller est déjà installé
echo -e "\n${YELLOW}🌐 Vérification de NGINX Ingress Controller...${NC}"
if kubectl get namespace ingress-nginx &> /dev/null; then
    echo -e "${GREEN}✅ NGINX Ingress Controller déjà installé${NC}"
else
    echo -e "${YELLOW}🌐 Installation de NGINX Ingress Controller...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    # Attendre que l'ingress controller soit prêt
    echo -e "${YELLOW}⏳ Attente du démarrage de NGINX Ingress Controller...${NC}"
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s
    
    echo -e "${GREEN}✅ NGINX Ingress Controller installé${NC}"
fi

# Mise à jour des repositories Helm
echo -e "\n${YELLOW}📦 Mise à jour des repositories Helm...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add gitea-charts https://dl.gitea.io/charts/
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo -e "${GREEN}✅ Repositories Helm mis à jour${NC}"

# Configuration des alias DNS locaux
echo -e "\n${YELLOW}🔧 Configuration des alias DNS locaux...${NC}"
cat << EOF
Ajoutez les lignes suivantes à votre fichier /etc/hosts (Linux/Mac) ou C:\\Windows\\System32\\drivers\\etc\\hosts (Windows):

127.0.0.1 keycloak.localhost
127.0.0.1 grafana.localhost
127.0.0.1 gitea.localhost
127.0.0.1 vault.localhost
127.0.0.1 prometheus.localhost
127.0.0.1 loki.localhost
EOF

echo -e "\n${GREEN}✅ Initialisation du cluster terminée avec succès!${NC}"
echo -e "${YELLOW}🚀 Vous pouvez maintenant exécuter: make deploy${NC}"
