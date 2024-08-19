variable "acr_server" {
  description = "Target Azure Container Registry."
  type        = string
}

variable "acr_server_subscription" {
  description = "Target Subscription ID."
  type        = string
}

variable "source_acr_client_id" {
  description = "Origin Client ID."
  type        = string
  sensitive   = true
}

variable "source_acr_client_secret" {
  description = "Origin Client Secret."
  type        = string
  sensitive   = true
}

variable "source_acr_server" {
  description = "Origin Azure Container Registry"
  type        = string
}

variable "charts" {
  description = "Helm charts List"
  type = list(object({
    chart_name       = string
    chart_namespace  = string
    chart_repository = string
    chart_version    = string
    values = list(object({
      name  = string
      value = string
    }))
    sensitive_values = list(object({
      name  = string
      value = string
    }))
  }))
}