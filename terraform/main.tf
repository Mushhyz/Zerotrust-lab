terraform {
  required_version = ">= 1.3.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.8"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.7"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand("~/.kube/config")
    config_context = "kind-kind"
  }
}

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "kind-kind"
}

resource "helm_release" "keycloak" {
  name             = "keycloak"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "keycloak"
  version          = "21.4.4"
  namespace        = "auth"
  create_namespace = true
  values           = [file("${path.module}/values/keycloak-values.yaml")]
  
  depends_on = [helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.28.1"
  namespace        = "vault"
  create_namespace = true
  values           = [file("${path.module}/values/vault-values.yaml")]
  
  depends_on = [helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
}

resource "helm_release" "gitea" {
  name             = "gitea"
  repository       = "https://dl.gitea.io/charts/"
  chart            = "gitea"
  version          = "10.1.4"
  namespace        = "gitea"
  create_namespace = true
  values           = [file("${path.module}/values/gitea-values.yaml")]
  
  depends_on = [helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "25.8.0"
  namespace        = "monitoring"
  create_namespace = true
  values           = [file("${path.module}/values/prometheus-values.yaml")]
  
  depends_on = [helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.3.7"
  namespace        = "monitoring"
  create_namespace = true
  values           = [file("${path.module}/values/grafana-values.yaml")]
  depends_on       = [helm_release.prometheus, helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
  max_history = 3
}

resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "5.43.3"
  namespace        = "logging"
  create_namespace = true
  values           = [file("${path.module}/values/loki-values.yaml")]
  
  depends_on = [helm_release.gatekeeper]
  
  # Non-blocking configuration
  timeout = 600  # 10 minutes
  wait    = false
  wait_for_jobs = false
  cleanup_on_fail = false
  atomic = false
}
