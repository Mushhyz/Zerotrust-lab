#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🚀 Déploiement de l'environnement Zero Trust (approche en 3 phases)${NC}"

# Vérifications préliminaires
echo -e "${YELLOW}🔍 Vérifications préliminaires...${NC}"

# Vérifier kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl n'est pas installé${NC}"
    echo -e "${YELLOW}💡 Exécutez: ./install-prerequisites.sh${NC}"
    exit 1
fi

# Vérifier la configuration kubectl
if [ ! -f ~/.kube/config ]; then
    echo -e "${RED}❌ Configuration kubectl manquante${NC}"
    echo -e "${YELLOW}💡 Exécutez d'abord: ./install-prerequisites.sh${NC}"
    exit 1
fi

# Vérifier l'accès au cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Impossible d'accéder au cluster Kubernetes${NC}"
    echo -e "${YELLOW}💡 Tentative de correction automatique...${NC}"
    
    if [ -f "./fix-kubectl.sh" ]; then
        chmod +x fix-kubectl.sh
        ./fix-kubectl.sh
    else
        echo -e "${YELLOW}💡 Vérifications suggérées:${NC}"
        echo "  - Docker fonctionne: docker ps"
        echo "  - Cluster kind existe: kind get clusters"
        echo "  - Reconfigurez kubectl: kind export kubeconfig"
        exit 1
    fi
fi

# Attendre que le cluster soit complètement prêt
echo -e "${YELLOW}⏳ Vérification que le cluster est prêt...${NC}"

# Vérifier que les pods DNS sont prêts
echo "  Attente des pods DNS..."
if ! kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=120s 2>/dev/null; then
    echo -e "${YELLOW}⚠️ Les pods DNS prennent du temps, continuons...${NC}"
fi

# Vérifier que l'ingress controller est prêt
echo "  Attente de l'ingress controller..."
if ! kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s 2>/dev/null; then
    echo -e "${YELLOW}⚠️ L'ingress controller prend du temps, continuons...${NC}"
    # Vérifier l'état des pods ingress
    kubectl get pods -n ingress-nginx 2>/dev/null || true
fi

echo -e "${GREEN}✅ Vérifications préliminaires réussies${NC}"

# Vérifier Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ terraform n'est pas installé${NC}"
    echo -e "${YELLOW}💡 Exécutez: ./install-prerequisites.sh${NC}"
    exit 1
fi

echo "🔧 Initialisation de Terraform..."
cd terraform
terraform init

echo "📦 Phase 1: Déploiement de Gatekeeper (OPA) en priorité..."
# Déployer uniquement OPA en premier
if ! terraform apply -target=helm_release.opa -auto-approve; then
    echo -e "${RED}❌ Échec du déploiement de Gatekeeper${NC}"
    exit 1
fi

echo "⏳ Attente que Gatekeeper soit complètement opérationnel..."
echo "  Phase 1a: Vérification du deployment controller-manager..."
if ! kubectl rollout status deployment/gatekeeper-controller-manager -n opa --timeout=300s; then
    echo -e "${YELLOW}⚠️ Timeout pour controller-manager, vérification manuelle...${NC}"
    kubectl get pods -n opa
fi

echo "  Phase 1b: Vérification du deployment audit..."
if ! kubectl rollout status deployment/gatekeeper-audit -n opa --timeout=180s; then
    echo -e "${YELLOW}⚠️ Timeout pour audit, vérification manuelle...${NC}"
    kubectl get pods -n opa
fi

echo "  Phase 1c: Attente que les webhooks soient prêts (60s)..."
sleep 60

echo "  Phase 1d: Vérification des pods Gatekeeper:"
kubectl get pods -n opa

echo "  Phase 1e: Vérification que les ValidatingAdmissionWebhooks sont prêts..."
if kubectl get validatingadmissionwebhook gatekeeper-validating-webhook-configuration &>/dev/null; then
    echo "    ✅ ValidatingAdmissionWebhook configuré"
else
    echo "    ⚠️ ValidatingAdmissionWebhook pas encore prêt, attente supplémentaire..."
    sleep 30
fi

echo "📦 Phase 2: Déploiement des ConstraintTemplates de base en priorité..."
echo "  Application des ConstraintTemplates de base via Terraform..."
if ! terraform apply -target=kubernetes_manifest.constrainttemplate_privileged -target=kubernetes_manifest.constrainttemplate_hostnetwork -target=kubernetes_manifest.constrainttemplate_latest_tag -target=kubernetes_manifest.constrainttemplate_resources -auto-approve; then
    echo -e "${YELLOW}⚠️ Problème avec les ConstraintTemplates de base, application manuelle...${NC}"
    
    # Application manuelle des templates de base
    echo "  Application manuelle des ConstraintTemplates de base..."
    kubectl apply -f ../opa/constraints/constrainttemplate-privileged.yaml || echo "    Failed: privileged"
    kubectl apply -f ../opa/constraints/constrainttemplate-hostnetwork.yaml || echo "    Failed: hostnetwork"
    kubectl apply -f ../opa/constraints/constrainttemplate-latest-tag.yaml || echo "    Failed: latest-tag"
    kubectl apply -f ../opa/constraints/constrainttemplate-resources.yaml || echo "    Failed: resources"
    
    echo "  Attente que les ConstraintTemplates de base s'établissent (60s)..."
    sleep 60
fi

echo "📦 Phase 2b: Déploiement des ConstraintTemplates avancés..."
echo "  Attente supplémentaire pour stabilité des templates de base (30s)..."
sleep 30

if ! terraform apply -target=kubernetes_manifest.constrainttemplate_hostpath -target=kubernetes_manifest.constrainttemplate_seccomp -target=kubernetes_manifest.constrainttemplate_image_digest -auto-approve; then
    echo -e "${YELLOW}⚠️ Problème avec les ConstraintTemplates avancés, tentative de récupération...${NC}"
    echo "  Vérification de l'état de Gatekeeper..."
    kubectl get pods -n opa
    kubectl get constrainttemplate
    
    echo "  Nouvelle tentative après attente (60s)..."
    sleep 60
    
    if ! terraform apply -target=kubernetes_manifest.constrainttemplate_hostpath -target=kubernetes_manifest.constrainttemplate_seccomp -target=kubernetes_manifest.constrainttemplate_image_digest -auto-approve; then
        echo -e "${RED}❌ Échec persistant des ConstraintTemplates avancés${NC}"
        echo -e "${YELLOW}💡 Continuons avec les templates de base seulement${NC}"
    fi
fi

echo "⏳ Phase 2c: Attente que tous les ConstraintTemplates s'établissent (90s)..."
sleep 90

echo "  Vérification des ConstraintTemplates créés:"
kubectl get constrainttemplate --no-headers | awk '{print "    - " $1}'

echo "📦 Phase 3: Déploiement des Constraints de base..."
echo "  Application des Constraints de base via Terraform..."
if ! terraform apply -target=kubernetes_manifest.constraint_deny_privileged -target=kubernetes_manifest.constraint_deny_hostnetwork -target=kubernetes_manifest.constraint_deny_latest_tag -target=kubernetes_manifest.constraint_require_resources -auto-approve; then
    echo -e "${YELLOW}⚠️ Problème avec les Constraints de base, application manuelle...${NC}"
    
    # Application manuelle des constraints de base
    echo "  Application manuelle des Constraints de base..."
    kubectl apply -f ../opa/constraints/constraint-deny-privileged.yaml || echo "    Failed: deny-privileged"
    kubectl apply -f ../opa/constraints/constraint-deny-hostnetwork.yaml || echo "    Failed: deny-hostnetwork"
    kubectl apply -f ../opa/constraints/constraint-deny-latest-tag.yaml || echo "    Failed: deny-latest-tag"
    kubectl apply -f ../opa/constraints/constraint-require-resources.yaml || echo "    Failed: require-resources"
fi

echo "📦 Phase 4: Déploiement des autres services..."
if ! terraform apply -auto-approve; then
    echo -e "${RED}❌ Échec du déploiement des services${NC}"
    echo -e "${YELLOW}💡 Informations de diagnostic:${NC}"
    echo "  État des ConstraintTemplates:"
    kubectl get constrainttemplate
    echo ""
    echo "  État des Constraints:"
    kubectl get constraints --all-namespaces
    echo ""
    echo -e "${YELLOW}💡 Solutions possibles:${NC}"
    echo "  - Attendre quelques minutes et réessayer: make deploy"
    echo "  - Nettoyer et redéployer: make reset && make deploy"
    echo "  - Déployer uniquement les politiques de base: make deploy-opa-basic"
    echo "  - Vérifier l'état de Gatekeeper: kubectl logs -n opa deployment/gatekeeper-controller-manager"
    exit 1
fi

echo "⏳ Attente du démarrage des services..."
echo "  Phase 1: Attente des pods critiques (30s)..."
sleep 30

# Vérifier que les pods critiques démarrent
echo "  Phase 2: Vérification des pods par namespace..."
for ns in auth vault gitea opa monitoring logging; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo "    Namespace $ns:"
        kubectl get pods -n "$ns" --no-headers 2>/dev/null | head -2 || echo "      Aucun pod trouvé"
    fi
done

echo "  Phase 3: Attente supplémentaire (30s)..."
sleep 30

echo "🌐 Application des manifests Ingress..."
cd ..

# Appliquer les ingress un par un avec vérification
for ingress_file in ingress-*.yaml; do
    if [ -f "$ingress_file" ]; then
        echo "  Applying $ingress_file..."
        kubectl apply -f "$ingress_file" || {
            echo -e "${YELLOW}⚠️ Échec de l'application de $ingress_file, continuons...${NC}"
        }
    fi
done

echo "🛡️ Application des politiques OPA Gatekeeper..."
if [ -d "opa/constraints" ]; then
    # Attendre que Gatekeeper soit prêt
    echo "  Attente que Gatekeeper soit prêt..."
    timeout 120 bash -c 'until kubectl get deployment gatekeeper-controller-manager -n opa &>/dev/null; do sleep 10; done' || {
        echo -e "${YELLOW}⚠️ Gatekeeper prend du temps à démarrer${NC}"
    }
    
    # Attendre que les webhooks soient prêts
    sleep 30
    
    # Appliquer les constraint templates d'abord
    for template_file in opa/constraints/constrainttemplate-*.yaml; do
        if [ -f "$template_file" ]; then
            echo "  Applying template: $(basename $template_file)"
            kubectl apply -f "$template_file" || {
                echo -e "${YELLOW}⚠️ Échec de l'application de $template_file${NC}"
            }
        fi
    done
    
    # Appliquer les templates avancés depuis GitOps
    if [ -d "gitops/opa/constraints/advanced-constraints" ]; then
        echo "  🔄 Les contraintes avancées sont maintenant gérées par Terraform..."
        echo "  ℹ️  Vérification que Terraform les a déployées..."
        
        # Vérifier que les ConstraintTemplates avancés sont déployés
        advanced_templates=("k8spsphostpath" "k8srequireseccomp" "k8srequireimagedigest")
        for template in "${advanced_templates[@]}"; do
            if kubectl get constrainttemplate "$template" &>/dev/null; then
                echo "    ✅ ConstraintTemplate $template trouvé"
            else
                echo "    ⚠️  ConstraintTemplate $template manquant - application manuelle..."
                template_file="gitops/opa/constraints/advanced-constraints/constrainttemplate-${template#k8s}.yaml"
                if [ -f "$template_file" ]; then
                    kubectl apply -f "$template_file" || {
                        echo -e "${YELLOW}⚠️ Échec de l'application de $template_file${NC}"
                    }
                fi
            fi
        done
        
        # Vérifier que les Constraints avancées sont déployées
        advanced_constraints=("deny-hostpath-volumes" "require-seccomp-runtime-default" "require-image-digest")
        for constraint in "${advanced_constraints[@]}"; do
            if kubectl get constraints --all-namespaces | grep -q "$constraint"; then
                echo "    ✅ Constraint $constraint trouvé"
            else
                echo "    ⚠️  Constraint $constraint manquant - application manuelle..."
                constraint_file="gitops/opa/constraints/advanced-constraints/constraint-${constraint#*-}.yaml"
                if [ -f "$constraint_file" ]; then
                    kubectl apply -f "$constraint_file" || {
                        echo -e "${YELLOW}⚠️ Échec de l'application de $constraint_file${NC}"
                    }
                fi
            fi
        done
    else
        echo "  ⚠️  Répertoire des contraintes avancées non trouvé"
        echo "  💡 Créez d'abord les contraintes avancées avec:"
        echo "      mkdir -p gitops/opa/constraints/advanced-constraints"
    fi
    
    # Attendre que les templates soient installés
    sleep 15
    
    # Puis appliquer les constraints
    for constraint_file in opa/constraints/constraint-*.yaml; do
        if [ -f "$constraint_file" ]; then
            echo "  Applying constraint: $(basename $constraint_file)"
            kubectl apply -f "$constraint_file" || {
                echo -e "${YELLOW}⚠️ Échec de l'application de $constraint_file${NC}"
            }
        fi
    done
    
    # Appliquer les constraints avancées depuis GitOps
    if [ -d "gitops/opa/constraints/advanced-constraints" ]; then
        echo "  Applying advanced constraints from GitOps..."
        for constraint_file in gitops/opa/constraints/advanced-constraints/constraint-*.yaml; do
            if [ -f "$constraint_file" ]; then
                echo "    Applying advanced constraint: $(basename $constraint_file)"
                kubectl apply -f "$constraint_file" || {
                    echo -e "${YELLOW}⚠️ Échec de l'application de $constraint_file${NC}"
                }
            fi
        done
    fi
    
    # Déployer l'application Argo CD pour les contraintes avancées
    echo "🚀 Configuration de la synchronisation Argo CD pour les contraintes avancées..."
    if [ -f "gitops/base/argo-root-app.yaml" ]; then
        echo "  📋 Application de l'application Argo CD root..."
        kubectl apply -f gitops/base/argo-root-app.yaml || {
            echo -e "${YELLOW}⚠️ Argo CD non disponible ou application déjà existante${NC}"
        }
        
        # Attendre la synchronisation
        echo "  ⏳ Attente de la synchronisation Argo CD (30s)..."
        sleep 30
        
        # Vérifier le statut de l'application
        if kubectl get application opa-advanced -n argocd &>/dev/null; then
            echo "  ✅ Application opa-advanced créée avec succès"
            app_status=$(kubectl get application opa-advanced -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Status indisponible")
            echo "  📊 Statut de synchronisation: $app_status"
        else
            echo "  ℹ️  Application opa-advanced sera gérée par Terraform"
        fi
    else
        echo "  ℹ️  Les contraintes avancées sont gérées par Terraform uniquement"
        echo "  📋 Vérification des ressources Terraform..."
        
        # Afficher le statut des contraintes depuis Terraform
        cd terraform
        terraform output opa_advanced_constraints_status 2>/dev/null || {
            echo "    ⚠️  Output Terraform non disponible"
        }
        cd ..
    fi
else
    echo -e "${YELLOW}⚠️ Répertoire opa/constraints non trouvé${NC}"
fi

echo "📋 Vérification du statut des deployments..."
echo -e "${BLUE}État des pods par namespace:${NC}"
for ns in auth vault gitea monitoring logging opa; do
    echo -e "${YELLOW}Namespace $ns:${NC}"
    kubectl get pods -n "$ns" --no-headers 2>/dev/null | head -3 || echo "  Namespace $ns vide ou inexistant"
done

# Vérification spécifique des contraintes OPA
echo -e "\n${YELLOW}🛡️ Vérification des politiques OPA déployées:${NC}"
echo "  ConstraintTemplates:"
kubectl get constrainttemplate --no-headers 2>/dev/null | awk '{print "    - " $1}' || echo "    Aucun ConstraintTemplate trouvé"

echo "  Constraints actives:"
kubectl get constraints --all-namespaces --no-headers 2>/dev/null | awk '{print "    - " $2 " (" $1 ")"}' || echo "    Aucune constraint trouvée"

echo -e "${GREEN}✅ Déploiement terminé avec succès.${NC}"
echo -e "${YELLOW}🔗 Services disponibles:${NC}"
echo "  - Keycloak: http://keycloak.localhost (admin/admin123)"
echo "  - Grafana: http://grafana.localhost (admin/admin123)"
echo "  - Vault: http://vault.localhost"
echo "  - Gitea: http://gitea.localhost"
echo ""
echo -e "${YELLOW}📋 Commandes utiles:${NC}"
echo "  - Valider le déploiement: make validate"
echo "  - Tester les politiques OPA: make validate-opa"
echo "  - Port-forwarding si ingress ne fonctionne pas:"
echo "    kubectl port-forward -n auth svc/keycloak 8080:80"
echo ""
echo -e "${BLUE}💡 Note: Les ingress peuvent prendre quelques minutes à être disponibles${NC}"
