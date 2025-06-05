terraform {
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

resource "helm_release" "gatekeeper" {
  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  version          = "3.14.0"
  namespace        = "opa"
  create_namespace = true
  values           = [file("${path.module}/../gitops/apps/opa/values.yaml")]

  wait          = true
  wait_for_jobs = true
  timeout       = 600
}

resource "time_sleep" "wait_for_gatekeeper" {
  depends_on = [helm_release.gatekeeper]
  create_duration = "180s"
}

# Basic ConstraintTemplates
resource "kubernetes_manifest" "constrainttemplate_privileged" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constrainttemplate-privileged.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_hostnetwork" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constrainttemplate-hostnetwork.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_latest_tag" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constrainttemplate-latest-tag.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_resources" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constrainttemplate-resources.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_required_labels" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constrainttemplate-required-labels.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

# Advanced ConstraintTemplates
resource "kubernetes_manifest" "constrainttemplate_hostpath" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constrainttemplate-hostpath.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_seccomp" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constrainttemplate-seccomp.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constrainttemplate_image_digest" {
  depends_on = [time_sleep.wait_for_gatekeeper]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constrainttemplate-image-digest.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "time_sleep" "wait_for_constraint_templates" {
  depends_on = [
    kubernetes_manifest.constrainttemplate_privileged,
    kubernetes_manifest.constrainttemplate_hostnetwork,
    kubernetes_manifest.constrainttemplate_latest_tag,
    kubernetes_manifest.constrainttemplate_resources,
    kubernetes_manifest.constrainttemplate_required_labels,
    kubernetes_manifest.constrainttemplate_hostpath,
    kubernetes_manifest.constrainttemplate_seccomp,
    kubernetes_manifest.constrainttemplate_image_digest
  ]
  create_duration = "120s"
}

# Basic Constraints
resource "kubernetes_manifest" "constraint_deny_privileged" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constraint-deny-privileged.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_deny_hostnetwork" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constraint-deny-hostnetwork.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_deny_latest_tag" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constraint-deny-latest-tag.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_require_resources" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constraint-require-resources.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_require_app" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../opa/constraints/constraint-require-app.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

# Advanced Constraints
resource "kubernetes_manifest" "constraint_deny_hostpath" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constraint-deny-hostpath.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_require_seccomp" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constraint-require-seccomp.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

resource "kubernetes_manifest" "constraint_require_image_digest" {
  depends_on = [time_sleep.wait_for_constraint_templates]
  manifest = yamldecode(file("${path.module}/../gitops/opa/constraints/advanced-constraints/constraint-require-image-digest.yaml"))
  timeouts {
    create = "5m"
    update = "3m"
    delete = "3m"
  }
  lifecycle {
    ignore_changes = [
      manifest.metadata.annotations,
      manifest.metadata.labels
    ]
  }
}

output "opa_advanced_constraints_status" {
  value = {
    gatekeeper_release = helm_release.gatekeeper.status
    # Basic constraint templates
    constrainttemplate_privileged = try(kubernetes_manifest.constrainttemplate_privileged.object.metadata.name, "pending")
    constrainttemplate_hostnetwork = try(kubernetes_manifest.constrainttemplate_hostnetwork.object.metadata.name, "pending")
    constrainttemplate_latest_tag = try(kubernetes_manifest.constrainttemplate_latest_tag.object.metadata.name, "pending")
    constrainttemplate_resources = try(kubernetes_manifest.constrainttemplate_resources.object.metadata.name, "pending")
    constrainttemplate_required_labels = try(kubernetes_manifest.constrainttemplate_required_labels.object.metadata.name, "pending")
    # Advanced constraint templates
    constrainttemplate_hostpath = try(kubernetes_manifest.constrainttemplate_hostpath.object.metadata.name, "pending")
    constrainttemplate_seccomp = try(kubernetes_manifest.constrainttemplate_seccomp.object.metadata.name, "pending")
    constrainttemplate_image_digest = try(kubernetes_manifest.constrainttemplate_image_digest.object.metadata.name, "pending")
    # Basic constraints
    constraint_deny_privileged = try(kubernetes_manifest.constraint_deny_privileged.object.metadata.name, "pending")
    constraint_deny_hostnetwork = try(kubernetes_manifest.constraint_deny_hostnetwork.object.metadata.name, "pending")
    constraint_deny_latest_tag = try(kubernetes_manifest.constraint_deny_latest_tag.object.metadata.name, "pending")
    constraint_require_resources = try(kubernetes_manifest.constraint_require_resources.object.metadata.name, "pending")
    constraint_require_app = try(kubernetes_manifest.constraint_require_app.object.metadata.name, "pending")
    # Advanced constraints
    constraint_deny_hostpath = try(kubernetes_manifest.constraint_deny_hostpath.object.metadata.name, "pending")
    constraint_require_seccomp = try(kubernetes_manifest.constraint_require_seccomp.object.metadata.name, "pending")
    constraint_require_image_digest = try(kubernetes_manifest.constraint_require_image_digest.object.metadata.name, "pending")
  }
  description = "Status of OPA Gatekeeper and all constraints deployment"
}
