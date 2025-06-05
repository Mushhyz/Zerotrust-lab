# Zero Trust Lab

This repository contains a Terraform configuration for deploying a Zero Trust security lab environment using Kubernetes and Helm charts.

## Hardware Requirements

### Remote Cluster Setup

#### Master Node (Kubernetes Control Plane)
- **CPU**: 2+ cores
- **RAM**: 4+ GB (8 GB recommended)
- **Storage**: 20+ GB free space
- **OS**: Linux (Ubuntu 20.04+)
- **Network**: Static IP recommended

#### Runner Machine (Deployment Client)
- **CPU**: 2+ cores
- **RAM**: 2+ GB (4 GB recommended)  
- **Storage**: 10+ GB free space
- **OS**: Linux (Ubuntu 20.04+)
- **Network**: SSH access to master node

## Architecture

The lab consists of the following components:

- **OPA Gatekeeper** (Policy Engine) - Namespace: `opa`
- **Keycloak** (Authentication & Authorization) - Namespace: `auth`
- **HashiCorp Vault** (Secrets Management) - Namespace: `vault`
- **Gitea** (Git Repository) - Namespace: `gitea`
- **Prometheus** (Monitoring & Metrics) - Namespace: `monitoring`
- **Grafana** (Visualization & Dashboards) - Namespace: `monitoring`
- **Loki** (Log Aggregation) - Namespace: `logging`

## Deployment Options

### Option 1: Local Deployment (Recommended for Development)

1. **Install Prerequisites**
    ```bash
    ./install-prerequisites.sh
    ```

2. **Deploy Environment**
    ```bash
    make deploy
    ```

### Option 2: Remote Cluster Deployment

⚠️ **Important**: You must initialize the runner machine BEFORE running `terraform apply`.

#### Step 1: Initialize Runner Machine

1. **Setup Runner Machine**
    ```bash
    cd runner/
    ./setup-runner.sh [MASTER_IP] [MASTER_PORT]
    ```

2. **Get Kubeconfig from Master**
    ```bash
    ./get-kubeconfig-master.sh [MASTER_IP] [USERNAME]
    ```

3. **Or Manual Kubeconfig Setup** (if step 2 fails)
    ```bash
    ./setup-kubeconfig-manual.sh [MASTER_IP] [USERNAME]
    ```

4. **Validate Runner Configuration**
    ```bash
    ./validate-runner.sh
    ```

#### Step 2: Deploy from Runner

Only after successful runner initialization:

```bash
make deploy
```

#### Prerequisites Before Terraform Apply

✅ **Checklist before running `terraform apply`:**

1. Master node has Kubernetes installed and running
2. Runner machine is properly configured with kubectl access
3. Runner can communicate with master node
4. All required tools are installed on runner (kubectl, helm, terraform)
5. Kubeconfig is properly configured and tested

## Deployed Services

| Service | Chart Version | Repository | Namespace |
|---------|---------------|------------|-----------|
| OPA Gatekeeper | 3.14.0 | OPA | opa |
| Keycloak | 21.4.4 | Bitnami | auth |
| Vault | 0.28.1 | HashiCorp | vault |
| Gitea | 10.1.4 | Gitea | gitea |
| Prometheus | 25.8.0 | Prometheus Community | monitoring |
| Grafana | 7.3.7 | Grafana | monitoring |
| Loki | 5.43.3 | Grafana | logging |

## Configuration Files

Each service has its own values file located in the `terraform/values/` directory:

- `opa-values.yaml`
- `keycloak-values.yaml`
- `vault-values.yaml`
- `gitea-values.yaml`
- `prometheus-values.yaml`
- `grafana-values.yaml`
- `loki-values.yaml`

## Access Services

### Configuration du fichier hosts

Ajoutez ces lignes dans votre fichier hosts pour accéder aux services via les noms de domaine locaux :

**Linux/macOS :** `/etc/hosts`
**Windows :** `C:\Windows\System32\drivers\etc\hosts`

```
192.168.1.53 gitea.localhost
192.168.1.53 grafana.localhost
192.168.1.53 keycloak.localhost
192.168.1.53 vault.localhost
```

Remplacez `192.168.1.53` par l'adresse IP de votre cluster Kubernetes.

### Via Ingress (if configured)
- Keycloak: http://keycloak.localhost
- Grafana: http://grafana.localhost
- Vault: http://vault.localhost
- Gitea: http://gitea.localhost

### Via Port-forwarding
```bash
# Keycloak
kubectl port-forward -n auth svc/keycloak 8080:80

# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Gitea
kubectl port-forward -n gitea svc/gitea-http 3001:3000
```

## Validation

```bash
# Full validation
make validate

# Quick validation
make validate-quick

# OPA policies validation
make validate-opa

# Cluster status
make validate-cluster
```

## OPA Gatekeeper Policies

The lab includes several OPA Gatekeeper policies for Zero Trust enforcement:

### Policy Templates
- **K8sRequiredLabels**: Enforce required labels on resources
- **K8sRequiredResources**: Enforce resource limits and requests
- **K8sPSPPrivileged**: Deny privileged containers
- **K8sPSPHostNetwork**: Deny hostNetwork usage
- **K8sDisallowLatestTag**: Prevent use of 'latest' image tags

### Advanced Policy Templates (GitOps)
- **K8sPSPHostPath**: Restrict hostPath volume usage
- **K8sRequireSeccomp**: Enforce seccomp profile (RuntimeDefault)
- **K8sRequireImageDigest**: Require image digest verification (@sha256:)

### Applied Constraints
- **require-app-label**: Requires 'app' label on pods and workloads
- **require-pod-resources**: Requires CPU/memory limits and requests
- **disallow-privileged**: Blocks privileged containers
- **disallow-hostnetwork**: Blocks hostNetwork usage
- **disallow-latest-tag**: Blocks 'latest' image tags

### Advanced Applied Constraints (GitOps)
- **deny-hostpath-volumes**: Blocks hostPath volume usage
- **require-seccomp-runtime-default**: Enforces RuntimeDefault seccomp profile
- **require-image-digest**: Requires SHA256 digest for container images

### Manual Policy Application

If policies fail during deployment, apply them step by step:

```bash
# Step 1: Apply basic constraint templates first
kubectl apply -f opa/constraints/constrainttemplate-privileged.yaml
kubectl apply -f opa/constraints/constrainttemplate-hostnetwork.yaml
kubectl apply -f opa/constraints/constrainttemplate-latest-tag.yaml
kubectl apply -f opa/constraints/constrainttemplate-resources.yaml

# Wait for templates to be ready
sleep 30

# Step 2: Apply advanced constraint templates from GitOps
kubectl apply -f gitops/opa/constraints/advanced-constraints/constrainttemplate-hostpath.yaml
kubectl apply -f gitops/opa/constraints/advanced-constraints/constrainttemplate-seccomp.yaml
kubectl apply -f gitops/opa/constraints/advanced-constraints/constrainttemplate-image-digest.yaml

# Wait for templates to be ready
sleep 30

# Step 3: Apply basic constraints
kubectl apply -f opa/constraints/constraint-deny-privileged.yaml
kubectl apply -f opa/constraints/constraint-deny-hostnetwork.yaml
kubectl apply -f opa/constraints/constraint-deny-latest-tag.yaml
kubectl apply -f opa/constraints/constraint-require-resources.yaml

# Step 4: Apply advanced constraints from GitOps
kubectl apply -f gitops/opa/constraints/advanced-constraints/constraint-deny-hostpath.yaml
kubectl apply -f gitops/opa/constraints/advanced-constraints/constraint-require-seccomp.yaml
kubectl apply -f gitops/opa/constraints/advanced-constraints/constraint-require-image-digest.yaml
```

### Alternative Deployment Methods

If the main deployment fails, try these alternatives:

```bash
# Deploy only basic OPA policies
make deploy-opa-basic

# Then deploy advanced OPA policies
make deploy-opa-advanced

# Or deploy step by step manually
cd terraform
terraform apply -target=helm_release.opa -auto-approve
terraform apply -target=kubernetes_manifest.constrainttemplate_privileged -auto-approve
terraform apply -target=kubernetes_manifest.constraint_deny_privileged -auto-approve
# Continue with other resources...
```

### Check Policy Status

```bash
# View constraint templates (basic + advanced)
kubectl get constrainttemplates

# View constraints (basic + advanced)
kubectl get constraints

# Check advanced constraints specifically
kubectl get k8spsphostpath,k8srequireseccomp,k8srequireimagedigest --all-namespaces

# Check violations
kubectl get constraints -o yaml | grep -A 10 violations

# Check Argo CD sync status
kubectl get application opa-advanced -n argocd -o jsonpath='{.status.sync.status}'
```

## Dependencies

All services depend on OPA (Open Policy Agent) being deployed first, ensuring proper policy enforcement throughout the Zero Trust architecture.

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

To remove the Kind cluster:

```bash
kind delete cluster --name kind
```

## Zero Trust Principles

This lab implements core Zero Trust principles:

- **Identity Verification**: Keycloak for authentication
- **Device Security**: Kubernetes RBAC and policies
- **Network Segmentation**: Namespace isolation
- **Application Security**: OPA policy enforcement
- **Data Protection**: Vault for secrets management
- **Monitoring**: Comprehensive logging and metrics

## Troubleshooting

### Common Issues

1. **Context not found**: Ensure Kind cluster is running and kubectl context is set
2. **Helm repository errors**: Run `helm repo update` to refresh repositories
3. **Resource conflicts**: Check if namespaces already exist

### Useful Commands

```bash
# Check cluster status
kubectl cluster-info

# List all pods across namespaces
kubectl get pods --all-namespaces

# Check Helm releases
helm list --all-namespaces

# View logs for troubleshooting
kubectl logs -n <namespace> <pod-name>
```

### Troubleshooting Remote Setup

**Runner initialization issues:**
- Ensure SSH connectivity to master: `ssh user@master`
- Check if master has Kubernetes: `ssh user@master 'kubectl version'`
- Verify kubeconfig location: `find /etc /home -name "*.conf" -o -name "config" 2>/dev/null`

**OPA Policy Issues:**
- Check Gatekeeper status: `kubectl get pods -n opa`
- View constraint templates: `kubectl get constrainttemplates`
- Check which CRDs are available: `kubectl get crd | grep gatekeeper`
- Manually apply failed policies step by step (see OPA section above)
- Check webhook configuration: `kubectl get validatingwebhookconfigurations`
- Deploy only basic policies first: `make deploy-opa-basic`

**Before Terraform Apply:**
- Test kubectl access: `kubectl cluster-info`
- Verify context: `kubectl config current-context`
- Check node status: `kubectl get nodes`

If kubeconfig is not found on master:
- Install Kubernetes on master node first
- Use manual kubeconfig setup script
- Ensure proper RBAC permissions

## Accès aux services

Après déploiement, ajoutez ces entrées à votre fichier hosts :

**Linux/Mac** (`/etc/hosts`) :
```
127.0.0.1   gitea.localhost
127.0.0.1   grafana.localhost
127.0.0.1   keycloak.localhost
127.0.0.1   vault.localhost
```

**Windows** (`C:\Windows\System32\drivers\etc\hosts`) :
```
127.0.0.1   gitea.localhost
127.0.0.1   grafana.localhost
127.0.0.1   keycloak.localhost
127.0.0.1   vault.localhost
```

### Vérification des services

```bash
curl -I http://gitea.localhost      # Doit retourner HTTP 200/302
curl -I http://grafana.localhost    # Doit retourner HTTP 200/302
curl -I http://keycloak.localhost   # Doit retourner HTTP 200/302
curl -I http://vault.localhost      # Doit retourner HTTP 200/302
```

### Accès aux interfaces

- **Gitea** : http://gitea.localhost (admin: gitea_admin / gitea_password)
- **Grafana** : http://grafana.localhost (admin: admin / admin123)
- **Keycloak** : http://keycloak.localhost (admin: admin / admin123)
- **Vault** : http://vault.localhost (token: vault-token)