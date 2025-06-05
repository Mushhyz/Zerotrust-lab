#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🛡️ Validation des politiques OPA Gatekeeper${NC}"
echo "=================================================="

# Check if OPA namespace exists
if ! kubectl get namespace opa &>/dev/null; then
    echo -e "${RED}❌ Namespace OPA non trouvé${NC}"
    echo -e "${YELLOW}💡 Déployez d'abord OPA: make deploy${NC}"
    exit 1
fi

# Check Gatekeeper pods
echo -e "${YELLOW}🔍 Vérification des pods Gatekeeper...${NC}"
kubectl get pods -n opa

# Check constraint templates
echo -e "\n${YELLOW}📋 ConstraintTemplates installés:${NC}"
if kubectl get constrainttemplates &>/dev/null; then
    kubectl get constrainttemplates
else
    echo -e "${RED}❌ Aucun ConstraintTemplate trouvé${NC}"
    echo -e "${YELLOW}💡 Appliquez les templates:${NC}"
    echo "kubectl apply -f opa/constraints/constrainttemplate-privileged.yaml"
    echo "kubectl apply -f opa/constraints/constrainttemplate-hostnetwork.yaml"
    echo "kubectl apply -f opa/constraints/constrainttemplate-latest-tag.yaml"
    echo "kubectl apply -f opa/constraints/constrainttemplate-resources.yaml"
fi

# Check constraints by specific types
echo -e "\n${YELLOW}📋 Constraints installés:${NC}"
constraint_types=("k8spspprivileged" "k8spsphostnetwork" "k8sdisallowlatesttag" "k8srequiredresources" "k8spsphostpath" "k8srequireseccomp" "k8srequireimagedigest")

for constraint_type in "${constraint_types[@]}"; do
    if kubectl get "$constraint_type" --all-namespaces &>/dev/null; then
        echo -e "${GREEN}✅ $constraint_type${NC}"
        kubectl get "$constraint_type" --all-namespaces --no-headers | awk '{print "    - " $2 " (" $1 ")"}'
    else
        echo -e "${RED}❌ $constraint_type non trouvé${NC}"
    fi
done

# Test policy enforcement
echo -e "\n${YELLOW}🧪 Test d'application des politiques...${NC}"

# Test 1: Pod with privileged security context (should be denied)
echo -e "${BLUE}Test 1: Pod avec contexte privilégié${NC}"
cat > /tmp/test-pod-privileged.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: default
  labels:
    app: test
spec:
  containers:
  - name: test
    image: nginx:1.20
    securityContext:
      privileged: true
EOF

if kubectl apply -f /tmp/test-pod-privileged.yaml --dry-run=server &>/dev/null; then
    echo -e "${YELLOW}⚠️ Pod privilégié accepté (mode warn)${NC}"
else
    echo -e "${GREEN}✅ Pod privilégié refusé par OPA${NC}"
fi

# Test 2: Pod with latest tag (should be denied/warned)
echo -e "${BLUE}Test 2: Pod avec tag 'latest'${NC}"
cat > /tmp/test-pod-latest.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-latest
  namespace: default
  labels:
    app: test
spec:
  containers:
  - name: test
    image: nginx:latest
EOF

if kubectl apply -f /tmp/test-pod-latest.yaml --dry-run=server &>/dev/null; then
    echo -e "${YELLOW}⚠️ Pod avec 'latest' accepté (mode warn)${NC}"
else
    echo -e "${GREEN}✅ Pod avec 'latest' refusé par OPA${NC}"
fi

# Test 3: Pod with hostPath volume (advanced constraint)
echo -e "${BLUE}Test 3: Pod avec volume hostPath${NC}"
cat > /tmp/test-pod-hostpath.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-hostpath
  namespace: default
  labels:
    app: test
spec:
  containers:
  - name: test
    image: nginx:1.20
  volumes:
  - name: host-vol
    hostPath:
      path: /etc
EOF

if kubectl apply -f /tmp/test-pod-hostpath.yaml --dry-run=server &>/dev/null; then
    echo -e "${YELLOW}⚠️ Pod avec hostPath accepté (contrainte avancée non active)${NC}"
else
    echo -e "${GREEN}✅ Pod avec hostPath refusé par OPA${NC}"
fi

# Test 4: Pod without seccomp profile (advanced constraint)
echo -e "${BLUE}Test 4: Pod sans profil seccomp${NC}"
cat > /tmp/test-pod-no-seccomp.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-no-seccomp
  namespace: default
  labels:
    app: test
spec:
  containers:
  - name: test
    image: nginx:1.20
EOF

if kubectl apply -f /tmp/test-pod-no-seccomp.yaml --dry-run=server &>/dev/null; then
    echo -e "${YELLOW}⚠️ Pod sans seccomp accepté (contrainte avancée non active)${NC}"
else
    echo -e "${GREEN}✅ Pod sans seccomp refusé par OPA${NC}"
fi

# Test 5: Valid pod with all security requirements (should succeed)
echo -e "${BLUE}Test 5: Pod valide avec toutes les exigences de sécurité${NC}"
cat > /tmp/test-pod-valid.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-valid
  namespace: default
  labels:
    app: test-valid
spec:
  containers:
  - name: test
    image: nginx:1.20@sha256:0d17b565c37bcbd895e9d92315a05c1c3c9a29f762b011a10c54a66cd53c9b31
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
EOF

if kubectl apply -f /tmp/test-pod-valid.yaml --dry-run=server &>/dev/null; then
    echo -e "${GREEN}✅ Pod valide accepté par OPA${NC}"
else
    echo -e "${RED}❌ Pod valide refusé - vérifiez les politiques${NC}"
fi

# Clean up test files
rm -f /tmp/test-pod-*.yaml

# Show policy status
echo -e "\n${YELLOW}📊 Statut des politiques:${NC}"
total_templates=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l)
total_constraints=0

for constraint_type in "${constraint_types[@]}"; do
    count=$(kubectl get "$constraint_type" --all-namespaces --no-headers 2>/dev/null | wc -l)
    total_constraints=$((total_constraints + count))
done

echo -e "${BLUE}Templates installés: ${total_templates}${NC}"
echo -e "${BLUE}Constraints installés: ${total_constraints}${NC}"

if [ "$total_templates" -gt 0 ] && [ "$total_constraints" -gt 0 ]; then
    echo -e "\n${GREEN}✅ Politiques OPA opérationnelles${NC}"
else
    echo -e "\n${RED}❌ Politiques OPA incomplètes${NC}"
    echo -e "${YELLOW}💡 Solutions:${NC}"
    echo "  make deploy-opa-basic"
    echo "  make deploy-opa-advanced"
    echo "  make reset && make deploy"
fi
