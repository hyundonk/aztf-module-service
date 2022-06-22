# aztf-module-service

This is terraform module for deploying azure virtual machine(s).

# input variable 
To create a VM, below variables shall be set. (mandatory ones)

```terraform
variable "resource_group_name" {
  description = "resource group name"
} 

variable "location" {
  description = "resource location"
}

variable "subnet_id" {
  description = "subnet ID"
}

variable "subnet_prefix" {
  description = "subnet prefix"
}

variable "admin_username" {
  description = "username for vm admin"
}

variable "admin_password" {
  description = "password for vm admin"
}
```

Also  you can specify VM details with "instances" variable. If omitted, a Ubuntu VM with below details will be deployed. 

``` 
variable "instances" {
  description = "VM instance configuration parameters"

  type = object({
    name              = string
    vm_num            = number # if vm_num == 3, myvm001, myvm002, myvm003 will be created.
    vm_size           = string
    subnet_ip_offset  = number

    vm_publisher      = string
    vm_offer          = string
    vm_sku            = string
    vm_version        = string
    prefix            = string
    postfix           = string
  })

  default = {
    name              = "myvm"
    vm_num            = 1
    vm_size           = "Standard_D4s_v3"
    subnet_ip_offset  = 4
    prefix            = null
    postfix           = null
    vm_publisher      = "Canonical"
    vm_offer          = "UbuntuServer"
    vm_sku            = "16.04.0-LTS"
    vm_version        = "latest"
  }
}
```

Below are optional variables. 

```
# if set, Will deploy MMA(Microsoft Monitoring Agent) VM  extension 
variable "log_analytics_workspace_id"  {
  description = "log analytics workspace ID for diagnostics log"
  default = null
}

# required for MMA VM Agent
variable "log_analytics_workspace_key"  {
  description = "log analytics workspace key for diagnostics log"
  default = null
}

# if set, Will deploy Network Watcher VM  extension 
variable "enable_network_watcher_extension" {
  description = "true to install network watcher extension"
  default = false
}

# if set, Will deploy dependency VM extension 
variable "enable_dependency_agent" {
  description = "true to install dependency agent"
  default = false
}

# deprecated 
variable "application_insights_key" {
  description = "application insights instrumentation key"
  default = null
}

# If set, VMs will be associated with a internal load balancer as backend VMs
variable "load_balancer_param" {
  description = "load balancer parameters"
  type = object({
    sku             = string
    probe_protocol  = string
    probe_port      = number
    probe_interval  = number
    probe_num       = number
  })

  default = null

  /* example
  default = {
      sku             = "basic"
      probe_protocol  = "Tcp"
      probe_port      = 22
      probe_interval  = 5
      probe_num       = 2
  }
  */
}

# If set, VMs will be associated with a load balancer outbound address pool for Internet outbound connectivity
variable "backend_outbound_address_pool_id" {
  description = "Backend Outbound Address Pool ID of external load balancer. This can be used for assign outbound public IP address pool"
  default = null
}

```

Example 1) Create a Ubuntu VM

```
# terraform.tfvars
prefix = "demo"
location = "koreacentral"

resource_groups = {
  RESOURCEGROUP1     = {
    name = "-resourcegroup1"
    location = "koreacentral"
  }
}

networking_object = {
  vnet = {
    name                = "-demo-vnet"
    address_space       = ["10.10.0.0/16"]
    dns                 = []
  }
  specialsubnets = {}

  subnets = {
    frontend   = {
      name                = "frontend"
      cidr                = "10.10.0.0/24"
      service_endpoints   = []
      nsg_name            = "frontend"
    }
  }
}

# ./example.tf
locals {
  RESOURCEGROUP = lookup(module.resource_group.names, "RESOURCEGROUP1", null)
  subnet        = var.networking_object.subnets.frontend.name
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

module "demo-vm" {
  source  = "github.com/hyundonk/aztf-module-vm"

  location                          = var.location
  resource_group_name               = local.RESOURCEGROUP

  subnet_id                         = module.virtual_network.subnet_ids_map[local.subnet]
  subnet_prefix                     = module.virtual_network.subnet_prefix_map[local.subnet]

  admin_username                    = var.adminusername
  admin_password                    = var.adminpassword
}
```


Example 2) Create 4 Windows VMs
```
module "demo-vm" {
  source  = "github.com/hyundonk/aztf-module-vm"

  location                          = var.location
  resource_group_name               = local.RESOURCEGROUP

  instances = {
    name          = "azuremgr"
    prefix            = null
    postfix           = null

    vm_num        = 4
    vm_size       = "Standard_F4s"
    subnet        = "subnet-management"
    subnet_ip_offset  = 13
    vm_publisher      = "MicrosoftWindowsServer"
    vm_offer          = "WindowsServer"
    vm_sku            = "2016-Datacenter"
    vm_version        = "latest"
  }
  
  subnet_id                         = module.virtual_network.subnet_ids_map[local.subnet]
  subnet_prefix                     = module.virtual_network.subnet_prefix_map[local.subnet]

  admin_username                    = var.adminusername
  admin_password                    = var.adminpassword
  
  boot_diagnostics_endpoint         = var.my_boot_diagnostics_endpoint
  custom_data                       = var.my_custom_data
  
  diag_storage_account_name         = var.my_diag_storage_account_name
  diag_storage_account_access_key   = var.my_diag_storage_account_access_key
  diag_storage_account_endpoint     = var.my_diag_storage_account_endpoint
  
  log_analytics_workspace_id        = var.my_log_analytics_workspace_id
  log_analytics_workspace_key       = var.my_log_analytics_workspace_key
  
  enable_network_watcher_extension  = var.my_enable_network_watcher_extension
  enable_dependency_agent           = var.my_enable_dependency_agent
}
```

## VM Naming convention

If no prefix is given
  vm_num = 1 ? {name} : {name}%03d{postfix}

If prefix is given
  {prefix}-{name}%03d{postfix}


