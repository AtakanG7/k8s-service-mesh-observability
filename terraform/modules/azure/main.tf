provider "azurerm" {
  features {}

  client_id       = var.ARM_CLIENT_ID
  client_secret   = var.ARM_CLIENT_SECRET
  tenant_id       = var.ARM_TENANT_ID
  subscription_id = var.ARM_SUBSCRIPTION_ID
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.kubernetes_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.kubernetes_cluster_name}-dns"

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"
  }
}

resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
  }
}

# Helm provider
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# Prometheus
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    templatefile("${path.module}/monitoring/prometheus-values.yaml", {
      grafana_password = random_password.grafana_admin_password.result
    })
  ]
}

#  AlertManager Config
resource "kubernetes_config_map" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = "monitoring"
  }

  data = {
    "alertmanager.yml"    = file("${path.module}/monitoring/alertmanager.yml")
    "prometheus-rules.yml" = file("${path.module}/monitoring/prometheus-rules.yml")
  }
}

# Add Istio
module "istio" {
  source = "../istio"

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Add Zipkin
module "zipkin" {
  source = "../zipkin"
  namespace = module.istio.istio_namespace

  depends_on = [module.istio]
}

# Configure Istio to use Zipkin
resource "kubernetes_config_map" "istio_config" {
  metadata {
    name = "istio-config"
    namespace = module.istio.istio_namespace
  }

  data = {
    "tracing.yaml" = <<EOF
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: tracing-default
  namespace: ${module.istio.istio_namespace}
spec:
  tracing:
  - providers:
    - name: zipkin
    randomSamplingPercentage: 100.0
EOF
  }

  depends_on = [module.istio, module.zipkin]
}

# Generate random password for Grafana admin
resource "random_password" "grafana_admin_password" {
  length  = 16
  special = true
}

