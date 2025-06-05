variable "keycloak_admin_password" {
  description = "Admin password for Keycloak"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = length(var.keycloak_admin_password) >= 8
    error_message = "Keycloak admin password must be at least 8 characters long."
  }
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "Grafana admin password must be at least 8 characters long."
  }
}

variable "gitea_admin_password" {
  description = "Admin password for Gitea"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = length(var.gitea_admin_password) >= 8
    error_message = "Gitea admin password must be at least 8 characters long."
  }
}

variable "oauth_client_secret" {
  description = "OAuth client secret for Grafana-Keycloak integration"
  type        = string
  default     = ""
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password for databases"
  type        = string
  default     = ""
  sensitive   = true
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}
