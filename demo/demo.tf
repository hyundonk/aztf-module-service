locals {
  RESOURCEGROUP = lookup(module.resource_group.names, "RESOURCEGROUP1", null)
  SUBNET        = var.networking_object.subnets.frontend.name
  adminusername = "azureuser"
  adminpassword = "Passw0rd!123"
}


module "resource_group" {
  source  = "aztfmod/caf-resource-group/azurerm"
  version = "0.1.1"

  prefix          = var.prefix
  resource_groups = var.resource_groups
  tags            = {}
}

module "virtual_network" {
  source  = "github.com/hyundonk/terraform-azurerm-caf-virtual-network"

  virtual_network_rg                = local.RESOURCEGROUP
  prefix                            = var.prefix
  location                          = var.location
  networking_object                 = var.networking_object
  tags            = {}
}

resource "random_string" "postfix" {
    length  = 4
    special = false
    upper   = false
    number  = false
}


resource "azurerm_storage_account" "example" {
  name                     = "diag${random_string.postfix.result}"
  resource_group_name      = local.RESOURCEGROUP
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

module "log_analytics" {
  source  = "aztfmod/caf-log-analytics/azurerm"
  version = "1.0.0"

  convention          = "cafrandom"
  prefix              = var.prefix
  name                = "diag${random_string.postfix.result}"
  solution_plan_map   = {}
  resource_group_name = local.RESOURCEGROUP
  location            = var.location
  tags                = null
}

resource "azurerm_public_ip" "example" {
  name                = "nat-gateway-pip"
  resource_group_name      = local.RESOURCEGROUP
  location                 = var.location
 
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "testvm" {
  name                = "testvm-pip"
  resource_group_name      = local.RESOURCEGROUP
  location                 = var.location
 
  allocation_method   = "Static"
  sku                 = "Standard"
}



resource "azurerm_nat_gateway" "example" {
  name                    = "nat-gateway"
  resource_group_name      = local.RESOURCEGROUP
  location                 = var.location
  public_ip_address_ids   = [azurerm_public_ip.example.id]

  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  subnet_id      = module.virtual_network.subnet_ids_map[local.SUBNET]
  nat_gateway_id = azurerm_nat_gateway.example.id
}

/*
output "diag_storage" {
  value = azurerm_storage_account.example
}
output "diag_la" {
  value = module.log_analytics.object
}
*/

module "demo-vm" {
  depends_on = [
    azurerm_subnet_nat_gateway_association.example,
  ]

  source  = "../"
  
  for_each          = { for x in jsondecode(file("./output.json")): x.servicename => x}

  name              = each.key
  instances			    = each.value

  location                          = var.location
  resource_group_name               = local.RESOURCEGROUP

  subnet_id                         = module.virtual_network.subnet_ids_map[local.SUBNET]
  subnet_prefix                     = module.virtual_network.subnet_prefix_map[local.SUBNET]

  admin_username                    = local.adminusername
  admin_password                    = local.adminpassword

  boot_diagnostics_endpoint         = azurerm_storage_account.example.primary_blob_endpoint
	
  diag_storage_account_name         = azurerm_storage_account.example.id
  diag_storage_account_access_key   = azurerm_storage_account.example.primary_access_key
  diag_storage_account_endpoint			= azurerm_storage_account.example.primary_blob_endpoint

  log_analytics_workspace_id        = null #module.log_analytics.object.workspace_id
  log_analytics_workspace_key       = null # module.log_analytics.object.primary_shared_key
  
  load_balancer_param               = var.load_balancer_param

  public_ip_id                      = azurerm_public_ip.testvm.id
}


