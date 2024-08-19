 #### Challenge 1
 
Because it seems that text relates to Azure, I've tried to focus solution in Azure AKS.

![Pasted image 20240819090726](https://github.com/user-attachments/assets/621273b7-2133-40dc-b944-e98f948d27c3)

- **Isolate specific node groups forbidding the pods scheduling in this node
groups.**

1. Proposed solution needs to label pool of nodes where it is going to be forbidden scheduling. Label assigned to these nodes will be `no-schedule=true`
```
az aks nodepool update --resource-group AKSResourceGroup --cluster-name AKSCluster --name NodePoolForbidden --labels "no-schedule=true"
```
Where:
- **AKSResourceGroup**: `<Resource Group name created in Azure>`
- **AKSCluster**: `<AKS Cluster Name created in Azure>`
- **NodePoolForbidden**: `<Name of Node Pool, set of nodes logically grouped with a name>`

2. Update deployment.yaml with new label

In `deployment.yaml`, it will be used `nodeAffinity` rule to ensure pods are not scheduled on nodes with previous label, so it is neccesary to update deployment section below:

```
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: no-schedule
                    operator: NotIn
                    values:
                      - "true"

```

- **Prevent Pods of the Same Type from Being Scheduled on the Same Node**

To ensure two pods of same type are not scheduled on node, it will be used **Pod Anti-Affinity**,
so it will be added section below to deployment manifest:

```
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - ping
              topologyKey: "kubernetes.io/hostname"
```

- **Deploy Pods Across Different Availability Zones**

In Azure,  AKS cluster in 3 availability zones is selected. Azure labels nodes with `topology.kubernetes.io/zone` label for pods.

Command `kubectl get nodes --show-labels` may be used to check this point is correct.

```
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: topology.kubernetes.io/zone
                    operator: In
                    values:
                      - "zone-1"
                      - "zone-2"
                      - "zone-3"
```

#### Challenge 2

### Terraform module hierarchy:

```
terraform-helm-acr-module
│ 
├── main.tf 
├── variables.tf 
├── outputs.tf 
└── README.md
```
### `variables.tf`**

```
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
    values           = list(object({
      name  = string
      value = string
    }))
    sensitive_values = list(object({
      name  = string
      value = string
    }))
  }))
}
```
### `main.tf`

```
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
      name  = value.name
      value = value.value
    }
  }

  depends_on = [null_resource.copy_helm_charts]
}
```
### `outputs.tf`

```
output "helm_release_status" {
  value = helm_release.helm_charts[*].status
}
```

### `values.tfvars`

```

```

### Initialization and Validations

**Initialization

```
➜  terraform-helm-acr-module git:(main) ✗ terraform init
Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/null...
- Finding hashicorp/azurerm versions matching "3.0.1"...
- Finding hashicorp/helm versions matching "~> 2.0"...
- Installing hashicorp/null v3.2.2...
- Installed hashicorp/null v3.2.2 (signed by HashiCorp)
- Installing hashicorp/azurerm v3.0.1...
- Installed hashicorp/azurerm v3.0.1 (signed by HashiCorp)
- Installing hashicorp/helm v2.15.0...
- Installed hashicorp/helm v2.15.0 (signed by HashiCorp)
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

**Format check

```
terraform fmt
```

**Validate
```
➜  terraform-helm-acr-module git:(main) ✗ terraform validate
Success! The configuration is valid.
```

**Plan
```
➜  terraform-helm-acr-module git:(main) ✗ terraform plan -out=tfplan

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the
following symbols:
  + create

Terraform will perform the following actions:

  # helm_release.helm_charts[0] will be created
  + resource "helm_release" "helm_charts" {
      + atomic                     = false
      + chart                      = "ping"
      + cleanup_on_fail            = false
      + create_namespace           = false
      + dependency_update          = false
      + disable_crd_hooks          = false
      + disable_openapi_validation = false
      + disable_webhooks           = false
      + force_update               = false
      + id                         = (known after apply)
      + lint                       = false
      + manifest                   = (known after apply)
      + max_history                = 0
      + metadata                   = (known after apply)
      + name                       = "ping"
      + namespace                  = "default"
      + pass_credentials           = false
      + recreate_pods              = false
      + render_subchart_notes      = true
      + replace                    = false
      + repository                 = "oci://instance.azurecr.io/charts"
      + reset_values               = false
      + reuse_values               = false
      + skip_crds                  = false
      + status                     = "deployed"
      + timeout                    = 300
      + values                     = [
          + "replicaCount=2",
          + "service.type=ClusterIP",
          + "service.port=80",
          + "autoscaling.enabled=false",
          + "ingress.enabled=false",
        ]
      + verify                     = false
      + version                    = "0.1.0"
      + wait                       = true
      + wait_for_jobs              = false

      + set_sensitive {
          # At least one attribute in this block is (or was) sensitive,
          # so its contents will not be displayed.
        }
    }

  # null_resource.copy_helm_charts[0] will be created
  + resource "null_resource" "copy_helm_charts" {
      + id = (known after apply)
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + helm_release_status = [
      + "deployed",
    ]

───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Saved the plan to: tfplan

To perform exactly these actions, run the following command to apply:
    terraform apply "tfplan"
```

#### Challenge 3

```
name: Deploy Helm Chart to AKS

on:
  push:
    branches:
      - main
  workflow_dispatch: # Manual Invocation from GitHub

jobs:
  deploy:
    runs-on: ubuntu-latest
