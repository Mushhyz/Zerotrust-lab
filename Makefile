.POSIX:
.SILENT:

.PHONY: deploy reset reset-force validate validate-opa validate-quick validate-cluster help clean wait-ready deploy-opa-basic deploy-opa-advanced fix-helm redeploy validate-runner

help:
	echo "🚀 Zero Trust Lab - Available Commands:"
	echo "  make validate-cluster - Check cluster status and readiness"
	echo "  make deploy       - Deploy all services"
	echo "  make deploy-opa-basic - Deploy basic OPA policies only"
	echo "  make deploy-opa-advanced - Deploy advanced OPA policies only"
	echo "  make wait-ready   - Wait for cluster to be completely ready"
	echo "  make reset        - Reset all resources"
	echo "  make reset-force  - Force reset with cluster recreation"
	echo "  make validate     - Full validation of deployment"
	echo "  make validate-opa - Test OPA policies specifically"
	echo "  make validate-quick - Quick validation (no external checks)"
	echo "  make validate-runner - Validate runner configuration"
	echo "  make clean        - Clean temporary files"
	echo "  make fix-helm     - Fix Helm timeout issues"
	echo "  make redeploy     - Redeploy failed services"

validate-cluster:
	echo "🔍 Vérification de l'état du cluster..."
	echo "📋 Nœuds du cluster:"
	kubectl get nodes
	echo ""
	echo "📦 Pods système (kube-system):"
	kubectl get pods -n kube-system
	echo ""
	echo "🌐 Pods ingress-nginx:"
	kubectl get pods -n ingress-nginx
	echo ""
	echo "🔗 Services ingress-nginx:"
	kubectl get svc -n ingress-nginx
	echo ""
	if kubectl get pods -n ingress-nginx --no-headers | grep -q "Running"; then \
		echo "✅ Ingress controller opérationnel"; \
	else \
		echo "⚠️ Ingress controller pas encore prêt"; \
		echo "💡 Attendez quelques minutes ou exécutez: ./fix-kubectl.sh"; \
	fi

wait-ready:
	echo "⏳ Attente que le cluster soit complètement prêt..."
	echo "📋 Vérification des pods système..."
	kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s
	echo "🌐 Vérification de l'ingress controller..."
	kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
	echo "✅ Cluster prêt pour le déploiement"

deploy: wait-ready
	echo "🔁 Déploiement en cours..."
	chmod +x deploy-all.sh
	./deploy-all.sh

deploy-opa-basic:
	echo "🛡️ Déploiement des politiques OPA de base..."
	chmod +x deploy-opa-only.sh
	./deploy-opa-only.sh

deploy-opa-advanced:
	echo "🛡️ Déploiement des politiques OPA avancées via Terraform..."
	cd terraform && terraform apply -target=kubernetes_manifest.constrainttemplate_hostpath -target=kubernetes_manifest.constrainttemplate_seccomp -target=kubernetes_manifest.constrainttemplate_image_digest -target=kubernetes_manifest.constraint_deny_hostpath -target=kubernetes_manifest.constraint_require_seccomp -target=kubernetes_manifest.constraint_require_image_digest -auto-approve

reset:
	echo "🧹 Réinitialisation en cours..."
	chmod +x reset-all.sh
	./reset-all.sh

reset-force:
	echo "💥 Réinitialisation forcée (suppression du cluster)..."
	kind delete cluster --name=kind || true
	echo "🔄 Recréation du cluster..."
	chmod +x install-prerequisites.sh
	./install-prerequisites.sh --cluster-only || echo "Utilisez install-prerequisites.sh pour recréer le cluster"

validate:
	echo "🔍 Validation complète en cours..."
	chmod +x validate.sh
	./validate.sh

validate-opa:
	echo "🛡️ Test des politiques OPA..."
	chmod +x validate-opa.sh
	./validate-opa.sh

validate-quick:
	echo "🔍 Validation rapide..."
	chmod +x validate.sh
	./validate.sh --quick

validate-runner:
	echo "🔍 Validation de la configuration du runner..."
	if [ -f "runner/validate.sh" ]; then \
		chmod +x runner/validate.sh; \
		./runner/validate.sh; \
	else \
		echo "❌ Script de validation runner non trouvé"; \
		echo "💡 Exécutez d'abord: ./runner/setup-runner.sh"; \
	fi

clean:
	echo "🧹 Nettoyage des fichiers temporaires..."
	find . -name "*.tmp" -delete 2>/dev/null || true
	find . -name "temp-*" -delete 2>/dev/null || true
	rm -f /tmp/test-pod-*.yaml 2>/dev/null || true
	rm -f /tmp/hostpath-test.log /tmp/digest-test.log 2>/dev/null || true
	echo "✅ Nettoyage terminé"

fix-helm:
	echo "🔧 Correction des timeouts Helm..."
	chmod +x fix-helm-timeouts.sh
	./fix-helm-timeouts.sh

redeploy:
	echo "🔄 Redéploiement des services échoués..."
	chmod +x redeploy-failed.sh
	./redeploy-failed.sh
