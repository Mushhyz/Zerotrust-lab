# Contraintes OPA Avancées - Guide GitOps

Ce document explique comment déployer et gérer les contraintes OPA avancées via GitOps dans l'environnement Zero Trust Lab.

## Vue d'ensemble

Les contraintes avancées ajoutent des politiques de sécurité renforcées :

- **K8sPSPHostPath** : Interdiction des volumes hostPath non autorisés
- **K8sRequireSeccomp** : Obligation d'utiliser le profil Seccomp RuntimeDefault
- **K8sRequireImageDigest** : Vérification des signatures d'images par digest SHA256

## Accès aux services

### Configuration /etc/hosts

Ajoutez ces entrées à votre fichier `/etc/hosts` pour accéder aux services :

```bash
# Zero Trust Lab Services - IP Master Node
192.168.1.53 keycloak.localhost
192.168.1.53 grafana.localhost
192.168.1.53 gitea.localhost
192.168.1.53 vault.localhost
192.168.1.53 prometheus.localhost
192.168.1.53 loki.localhost
```

### Services accessibles via 192.168.1.53

| Service | URL | Credentials | Description |
|---------|-----|-------------|-------------|
| **Keycloak** | http://keycloak.localhost | admin/admin123 | Authentification & Authorization |
| **Grafana** | http://grafana.localhost | admin/admin123 | Visualisation & Dashboards |
| **Gitea** | http://gitea.localhost | gitea_admin/gitea_password | Git Repository |
| **Vault** | http://vault.localhost | Token: root | Secrets Management |
| **Prometheus** | http://prometheus.localhost | - | Monitoring & Metrics |
| **Loki** | http://loki.localhost | - | Log Aggregation |

### Port-forwarding alternatif

Si l'ingress ne fonctionne pas, utilisez le port-forwarding :

```bash
# Keycloak
kubectl port-forward -n auth svc/keycloak 8080:80
# Accès: http://192.168.1.53:8080

# Grafana  
kubectl port-forward -n monitoring svc/grafana 3000:80
# Accès: http://192.168.1.53:3000

# Gitea
kubectl port-forward -n gitea svc/gitea-http 3001:3000
# Accès: http://192.168.1.53:3001

# Vault
kubectl port-forward -n vault svc/vault 8200:8200
# Accès: http://192.168.1.53:8200

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Accès: http://192.168.1.53:9090

# Loki
kubectl port-forward -n logging svc/loki 3100:3100
# Accès: http://192.168.1.53:3100
```

## Structure des fichiers

```
gitops/opa/constraints/advanced-constraints/
├── constrainttemplate-hostpath.yaml      # Template pour hostPath
├── constraint-deny-hostpath.yaml         # Contrainte hostPath
├── constrainttemplate-seccomp.yaml       # Template pour Seccomp
├── constraint-require-seccomp.yaml       # Contrainte Seccomp
├── constrainttemplate-image-digest.yaml  # Template pour digest
└── constraint-require-image-digest.yaml  # Contrainte digest
```

## Déploiement GitOps

### 1. Ajouter les fichiers au repository Git

```bash
# Ajouter les nouveaux fichiers
git add gitops/opa/constraints/advanced-constraints/
git add gitops/opa/values.yaml
git add gitops/opa/kustomization.yaml

# Créer le commit
git commit -m "feat: Add advanced OPA constraints for Zero Trust security

- Add hostPath volume restrictions
- Add seccomp profile enforcement 
- Add image digest verification
- Configure Argo CD integration"

# Pousser vers le repository
git push origin main
```

### 2. Configuration Argo CD

Les contraintes sont automatiquement synchronisées grâce aux annotations :

```yaml
annotations:
  argocd.argoproj.io/sync-wave: "2"    # Templates en premier
  argocd.argoproj.io/sync-wave: "3"    # Contraintes ensuite
```

## Politiques de sécurité

### Interdiction des hostPath

- **Objectif** : Empêcher l'accès direct au système de fichiers de l'hôte
- **Namespaces exclus** : kube-system, ingress-nginx, local-path-storage
- **Configuration** : Aucun chemin hostPath autorisé par défaut

### Profil Seccomp obligatoire

- **Objectif** : Renforcer l'isolation des conteneurs
- **Profils autorisés** : RuntimeDefault, Localhost
- **Application** : Tous les conteneurs et init containers

### Vérification des signatures d'images

- **Objectif** : Assurer l'intégrité des images déployées
- **Requis** : Digest SHA256 (@sha256:) au lieu de tags
- **Images exemptées** : Images système temporairement (gcr.io/kubebuilder/, registry.k8s.io/)

## Validation et tests

### Vérifier le déploiement

```bash
# Vérifier les ConstraintTemplates
kubectl get constrainttemplate

# Vérifier les contraintes actives
kubectl get constraints --all-namespaces

# Vérifier les violations
kubectl describe k8spsphostpath deny-hostpath-volumes
kubectl describe k8srequireseccomp require-seccomp-runtime-default
kubectl describe k8srequireimagedigest require-image-digest
```

### Accès depuis le runner/client

Si vous accédez depuis une machine différente de 192.168.1.53, ajoutez à votre `/etc/hosts` :

```bash
# Sur votre machine cliente (non le serveur 192.168.1.53)
192.168.1.53 keycloak.localhost
192.168.1.53 grafana.localhost  
192.168.1.53 gitea.localhost
192.168.1.53 vault.localhost
192.168.1.53 prometheus.localhost
192.168.1.53 loki.localhost
```

### Test de connectivité

```bash
# Tester la résolution DNS
nslookup grafana.localhost
ping grafana.localhost

# Tester l'accès HTTP
curl -I http://grafana.localhost
curl -I http://keycloak.localhost
```

## Configuration réseau

### Depuis le master (192.168.1.53)

```bash
# Vérifier les services Kubernetes
kubectl get svc --all-namespaces

# Vérifier les ingress
kubectl get ingress --all-namespaces

# Vérifier le statut des pods
kubectl get pods --all-namespaces
```

### Depuis une machine distante

```bash
# SSH vers le master
ssh manager@192.168.1.53

# Tunnel SSH pour port-forwarding
ssh -L 3000:localhost:3000 manager@192.168.1.53
ssh -L 8080:localhost:8080 manager@192.168.1.53
```

## Commandes utiles

```bash
# Validation complète
make validate

# Validation OPA spécifique  
make validate-opa

# Debug des contraintes
kubectl get events --field-selector reason=FailedCreate
kubectl logs -n opa -l app.kubernetes.io/name=gatekeeper

# Vérifier l'ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Synchronisation Argo CD

Les contraintes sont organisées par vagues de synchronisation :

1. **Wave 1** : Déploiement d'OPA Gatekeeper
2. **Wave 2** : Application des ConstraintTemplates
3. **Wave 3** : Application des Constraints

Cette approche assure un déploiement ordonné et évite les conflits de dépendances.

## Troubleshooting réseau

### Ingress ne répond pas

1. Vérifiez l'ingress controller :
   ```bash
   kubectl get pods -n ingress-nginx
   kubectl describe ingress -n monitoring grafana-ingress
   ```

2. Vérifiez la résolution DNS :
   ```bash
   cat /etc/hosts | grep localhost
   ```

3. Utilisez le port-forwarding comme alternative

### Contraintes non appliquées

1. Vérifiez que Gatekeeper est en cours d'exécution :
   ```bash
   kubectl get pods -n opa
   ```

2. Vérifiez les logs Gatekeeper :
   ```bash
   kubectl logs -n opa -l app=gatekeeper-controller-manager
   ```

3. Réappliquez les templates si nécessaire :
   ```bash
   kubectl apply -f gitops/opa/constraints/advanced-constraints/
   ```

## Correction Terraform (CRD not recognized)
Pour éviter l’erreur “no matches for kind … in group constraints.gatekeeper.sh”, installez d’abord Gatekeeper et ses CRD avant de créer vos Constraint & ConstraintTemplate. Exemple minimal :

```hcl
resource "helm_release" "gatekeeper" {
  // ...existing code...
}
resource "time_sleep" "wait_for_crds" {
  depends_on      = [helm_release.gatekeeper]
  create_duration = "30s"
}
resource "kubernetes_manifest" "constrainttemplate_example" {
  manifest = file("${path.module}/constrainttemplate-example.yaml")
  depends_on = [time_sleep.wait_for_crds]
}
resource "kubernetes_manifest" "constraint_example" {
  // ...existing code...
  depends_on = [kubernetes_manifest.constrainttemplate_example]
}
```

## Évolution

Pour ajouter de nouvelles contraintes :

1. Créez les fichiers dans `gitops/opa/constraints/advanced-constraints/`
2. Mettez à jour `kustomization.yaml`
3. Committez et poussez vers Git
4. Argo CD synchronise automatiquement

Cette approche GitOps assure la traçabilité et la reproductibilité des politiques de sécurité avec un accès réseau via 192.168.1.53.
