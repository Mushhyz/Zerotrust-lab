output "keycloak_admin_user" {
  description = "Keycloak admin username"
  value       = "admin"
}

output "grafana_admin_user" {
  description = "Grafana admin username"
  value       = "admin"
}

output "gitea_admin_user" {
  description = "Gitea admin username"
  value       = "gitea_admin"
}

output "deployment_namespaces" {
  description = "List of created namespaces"
  value       = ["auth", "vault", "gitea", "opa", "monitoring", "logging"]
}

output "deployment_status" {
  description = "Overall deployment status"
  value = {
    # Service status
    services_deployed = {
      keycloak = try(helm_release.keycloak.status, "not_deployed")
      vault = try(helm_release.vault.status, "not_deployed")
      gitea = try(helm_release.gitea.status, "not_deployed")
      prometheus = try(helm_release.prometheus.status, "not_deployed")
      grafana = try(helm_release.grafana.status, "not_deployed")
      loki = try(helm_release.loki.status, "not_deployed")
      gatekeeper = try(helm_release.gatekeeper.status, "not_deployed")
    }
    
    # OPA constraints status
    opa_constraints = {
      basic_templates = {
        privileged = try(kubernetes_manifest.constrainttemplate_privileged.object.metadata.name, "missing")
        hostnetwork = try(kubernetes_manifest.constrainttemplate_hostnetwork.object.metadata.name, "missing")
        latest_tag = try(kubernetes_manifest.constrainttemplate_latest_tag.object.metadata.name, "missing")
        resources = try(kubernetes_manifest.constrainttemplate_resources.object.metadata.name, "missing")
      }
      advanced_templates = {
        hostpath = try(kubernetes_manifest.constrainttemplate_hostpath.object.metadata.name, "missing")
        seccomp = try(kubernetes_manifest.constrainttemplate_seccomp.object.metadata.name, "missing")
        image_digest = try(kubernetes_manifest.constrainttemplate_image_digest.object.metadata.name, "missing")
      }
    }
  }
}

output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting"
  value = {
    check_pods = "kubectl get pods --all-namespaces"
    check_constraints = "kubectl get k8spspprivileged,k8spsphostnetwork,k8sdisallowlatesttag,k8srequiredresources --all-namespaces"
    check_violations = "kubectl get k8spspprivileged,k8spsphostnetwork,k8sdisallowlatesttag,k8srequiredresources -o yaml"
    grafana_logs = "kubectl logs -n monitoring deployment/grafana"
    gatekeeper_logs = "kubectl logs -n opa deployment/gatekeeper-controller-manager"
    port_forward_grafana = "kubectl port-forward -n monitoring svc/grafana 3000:80"
    helm_status = "helm list --all-namespaces"
    check_helm_keycloak = "helm status keycloak -n auth"
    check_helm_prometheus = "helm status prometheus -n monitoring"
    check_resources = "kubectl top nodes && kubectl top pods --all-namespaces"
    restart_stuck_deployments = "kubectl rollout restart deployment --all-namespaces"
  }
}
