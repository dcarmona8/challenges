terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features = {}
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "null_resource" "copy_helm_charts" {
  count = length(var.charts)

  provisioner "local-exec" {
    command = <<EOT
      az acr helm repo add --name ${var.acr_server} --subscription ${var.acr_server_subscription}
      az acr login --name ${var.acr_server}
      az acr helm repo add --name ${var.source_acr_server} --subscription ${var.acr_server_subscription} --username ${var.source_acr_client_id} --password ${var.source_acr_client_secret}
      helm registry login ${var.source_acr_server} --username ${var.source_acr_client_id} --password ${var.source_acr_client_secret}
      helm pull oci://${var.source_acr_server}/${var.charts[count.index].chart_repository} --version ${var.charts[count.index].chart_version} -d /tmp/charts
      helm push /tmp/charts/${var.charts[count.index].chart_name}-${var.charts[count.index].chart_version}.tgz oci://${var.acr_server}/${var.charts[count.index].chart_repository}
    EOT
  }
}

resource "helm_release" "helm_charts" {
  count = length(var.charts)

  name       = var.charts[count.index].chart_name
  namespace  = var.charts[count.index].chart_namespace
  repository = "oci://${var.acr_server}/${var.charts[count.index].chart_repository}"
  chart      = var.charts[count.index].chart_name
  version    = var.charts[count.index].chart_version

  values = [
    for value in var.charts[count.index].values :
    "${value.name}=${value.value}"
  ]

  dynamic "set_sensitive" {
    for_each = var.charts[count.index].sensitive_values
    content {
      name  = set_sensitive.value.name
      value = set_sensitive.value.value
    }
  }

  depends_on = [null_resource.copy_helm_charts]
}
