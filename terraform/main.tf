provider "azurerm" {
  features {}

  client_id       = var.CLIENT_ID
  client_secret   = var.CLIENT_SECRET
  tenant_id       = var.TENANT_ID
  subscription_id = var.SUBSCRIPTION_ID
}

resource "azurerm_resource_group" "bdcc" {
  name     = "rg${var.ENV}${var.LOCATION}"
  location = var.LOCATION

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_storage_account" "bdcc" {
  name                     = "st${var.ENV}${var.LOCATION}"
  resource_group_name      = azurerm_resource_group.bdcc.name
  location                 = azurerm_resource_group.bdcc.location
  account_tier             = "Standard"
  account_replication_type = var.STORAGE_ACCOUNT_REPLICATION_TYPE
  is_hns_enabled           = true
  allow_blob_public_access = true

  network_rules {
    default_action = "Allow"
    ip_rules       = values(var.IP_RULES)
  }

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_storage_container" "bdcc" {
  name                  = "data${var.ENV}${var.LOCATION}"
  storage_account_name  = azurerm_storage_account.bdcc.name
  container_access_type = "blob"

  lifecycle {
    prevent_destroy = false
  }
}

resource "azurerm_storage_blob" "bdcc" {
  for_each               = fileset(path.module, "../m12kafkastreams/topics/expedia/**")
  name                   = "${replace(each.key, "../m12kafkastreams/", "")}"
  storage_account_name   = azurerm_storage_account.bdcc.name
  storage_container_name = azurerm_storage_container.bdcc.name
  type                   = "Block"
  source                 = each.key
}

resource "azurerm_container_registry" "bdcc" {
  name                = "acr${var.ENV}${var.LOCATION}"
  resource_group_name = azurerm_resource_group.bdcc.name
  location            = azurerm_resource_group.bdcc.location
  sku                 = "Standard"
  admin_enabled       = true

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

resource "azurerm_kubernetes_cluster" "bdcc" {
  name                = "aks${var.ENV}${var.LOCATION}"
  location            = azurerm_resource_group.bdcc.location
  resource_group_name = azurerm_resource_group.bdcc.name
  dns_prefix          = "bdcc${var.ENV}"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_D2_v2"
  }

  service_principal {
    client_id     = var.CLIENT_ID
    client_secret = var.CLIENT_SECRET
  }

  tags = {
    region = var.BDCC_REGION
    env    = var.ENV
  }
}

data "azurerm_kubernetes_cluster" "bdcc" {
  name                = azurerm_kubernetes_cluster.bdcc.name
  resource_group_name = azurerm_kubernetes_cluster.bdcc.resource_group_name
}

output "storage_account_name" {
  value     = azurerm_storage_account.bdcc.name
  sensitive = true
}

output "storage_container_name" {
  value     = azurerm_storage_container.bdcc.name
  sensitive = true
}

output "resource_group_name" {
  value     = azurerm_resource_group.bdcc.name
  sensitive = true
}

output "acr_login_server" {
  value     = azurerm_container_registry.bdcc.login_server
  sensitive = true
}

output "acr_name" {
  value     = azurerm_container_registry.bdcc.name
  sensitive = true
}

output "kubernetes_cluster_name" {
  value     = azurerm_kubernetes_cluster.bdcc.name
  sensitive = true
}

output "kubernetes_cluster_host" {
  value     = data.azurerm_kubernetes_cluster.bdcc.kube_config.0.host
  sensitive = true
}
