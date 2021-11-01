locals {
  merged_instances      = merge(var.instances_defaults, var.instances) 

  vm_size								= local.merged_instances.vm_size
  subnet_ip_offset			= local.merged_instances.subnet_ip_offset
  #vm_publisher					= local.merged_instances.vm_publisher
  vm_offer							= local.merged_instances.vm_offer
  #vm_sku								= local.merged_instances.vm_sku
  #vm_version						= local.merged_instances.vm_version
  
  storageAccountName    = var.diag_storage_account_name == null ? null : element(split("/", var.diag_storage_account_name), 8)
  enable_accelerated_networking = local.vm_size == "Standard_D2s_v3" ? "false" : "true"
}

resource "azurerm_availability_set" "avset" {
  count                         = var.load_balancer_param == null ? 0 : 1 # create only if load balancer exists

  name                  	      = "${var.name}-avset"
  location              	      = var.location
  resource_group_name  	        = var.resource_group_name
	
  platform_update_domain_count  = var.update_domain_count
  platform_fault_domain_count   = var.fault_domain_count

  managed                       = true
	
  proximity_placement_group_id	= var.enable_proximity_place_group == true ? azurerm_proximity_placement_group.ppg.0.id : null
}

resource "azurerm_proximity_placement_group" "ppg" {
  count                         = var.enable_proximity_place_group == true ? 1 : 0 # create only if multiple instances cases

  name                          = "${var.name}-ppg"
  location                      = var.location
  resource_group_name           = var.resource_group_name
}

resource "azurerm_network_interface" "nic" {
  for_each = { for x in var.instances.vm: x.name => x }
  #for_each				                      = var.instances.vm

  name         													= "${each.value.name}-nic"

  location            	                = var.location
  resource_group_name  	                = var.resource_group_name
	
  ip_configuration {
    name 															= "ipconfig0"
    subnet_id 												= var.subnet_id
    private_ip_address_allocation     = "static"
    private_ip_address                = each.value.ipaddress 
    public_ip_address_id              = var.public_ip_id     == null ? null : var.public_ip_id
  }
  
  enable_accelerated_networking       	= local.enable_accelerated_networking
}

resource "azurerm_virtual_machine" "vm" {
  lifecycle {
    ignore_changes = [ # don't recreate existing disk
      storage_os_disk,
      tags
		]
  }

  #for_each				                      = var.instances.vm
  for_each = { for x in var.instances.vm: x.name => x }

  name                  								= each.value.name

  location        	   	                = var.location
  resource_group_name 	                = var.resource_group_name
  vm_size               	              = local.vm_size

  delete_os_disk_on_termination 				= true
  delete_data_disks_on_termination 			= true

  availability_set_id                   = var.load_balancer_param == null ? null : azurerm_availability_set.avset.0.id

  proximity_placement_group_id          = var.enable_proximity_place_group == true ? azurerm_proximity_placement_group.ppg.0.id : null

  storage_image_reference {
    id                    = each.value.image_id
    publisher             = null
    offer                 = null
    sku                   = null
    version               = null
  }

  storage_os_disk {
    name        	        = "${each.value.name}-osdisk"
    caching       		    = "ReadWrite"
    create_option 		    = "FromImage"
    managed_disk_type     = "Standard_LRS"
    disk_size_gb          = 300
  }

  identity { # added to enable 'Azure Monitor Sink' feature
    type = "SystemAssigned"
  }

  os_profile {
    computer_name					= each.value.name
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    custom_data           = var.custom_data == null ? null : var.custom_data
    #custom_data           = var.custom_data == null ? null : filebase64(var.custom_data)
  }
/*  
  dynamic "storage_data_disk" {
    for_each = var.data_disk == null ? [] : ["DataDisk"]
    content {
      name        	      = var.data_disk.name
      managed_disk_id     = var.data_disk.id
      create_option       = "Attach"
      lun                 = 0
      disk_size_gb        = var.data_disk.size
    }
  }
*/ 
  dynamic "storage_data_disk" {
    for_each = var.data_disk
    content {
      name        	      = format("%s-datadisk-%02d", each.value.name, storage_data_disk.key)
      managed_disk_type   = storage_data_disk.value.type
      create_option       = "Empty"
      lun                 = storage_data_disk.key
      disk_size_gb        = storage_data_disk.value.disk_size
    }
  }
 
  dynamic "os_profile_windows_config" {
    for_each = local.vm_offer == "WindowsServer" ? ["WindowsServer"] : []
    content {
      provision_vm_agent    = true
    }
  }

  dynamic "os_profile_linux_config" {
    for_each = local.vm_offer == "WindowsServer" ? [] : var.ssh_key_data != null ? [1] : []
    content {
      disable_password_authentication = true
      ssh_keys {
        key_data  = var.ssh_key_data
        path      = var.ssh_key_path
      }
    }

  }
	
  dynamic "os_profile_linux_config" {
    for_each = local.vm_offer == "WindowsServer" ? [] : var.ssh_key_data != null ? [] : [1]
    content {
      disable_password_authentication = false
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics_endpoint == null ? [] : ["BootDiagnostics"]
    content {
      enabled               = var.boot_diagnostics_endpoint != null ? true : false
      storage_uri           = var.boot_diagnostics_endpoint
    }
  }

  #network_interface_ids  = [element(azurerm_network_interface.nic.*.id, count.index)]
  #network_interface_ids   = [element(concat(azurerm_network_interface.nic.*.id, list("")), count.index)]
  network_interface_ids   = [azurerm_network_interface.nic[each.key].id]

  license_type            = local.vm_offer == "WindowsServer" ? var.license_type : null

  tags = var.tags
}

resource "azurerm_network_interface_backend_address_pool_association" "association" {
  #for_each                  = var.instances.vm
  for_each = { for x in var.instances.vm: x.name => x }

  network_interface_id      = azurerm_network_interface.nic[each.key].id
  ip_configuration_name     = "ipconfig0"
  backend_address_pool_id   = azurerm_lb_backend_address_pool.lb.0.id
}

resource "azurerm_network_interface_backend_address_pool_association" "association_outbound" {
  for_each                  = var.backend_outbound_address_pool_id == null ? {} : { for x in var.instances.vm: x.name => x }

	network_interface_id      = azurerm_network_interface.nic[each.key].id
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_outbound_address_pool_id
}


resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "association" {
	for_each                  = var.backend_address_pool_id == null ? {} : { for x in var.instances.vm: x.name => x }
	
	network_interface_id      = azurerm_network_interface.nic[each.key].id
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_address_pool_id
}

# Refer https://docs.microsoft.com/en-us/azure/azure-monitor/platform/diagnostics-extension-schema-windows
resource "azurerm_virtual_machine_extension" "diagnostics" {
	for_each                      = var.diag_storage_account_name == null ? {} : local.vm_offer == "WindowsServer" ? { for x in var.instances.vm: x.name => x } : {}
	
	name                          = "Microsoft.Insights.VMDiagnosticsSettings"
	#location              	      = var.location
	#resource_group_name  	        = var.resource_group_name

	virtual_machine_id						= azurerm_virtual_machine.vm[each.key].id
	#virtual_machine_name   	      = element(azurerm_virtual_machine.vm.*.name, count.index)

	publisher            	        = "Microsoft.Azure.Diagnostics"
	type                 	        = "IaaSDiagnostics"
	type_handler_version 	        = "1.5"

	auto_upgrade_minor_version    = true

	settings = <<SETTINGS
	{
		"xmlCfg"            :  "${base64encode(templatefile("${path.module}/wadcfgxml.tmpl", { resource_id = azurerm_virtual_machine.vm[each.key].id}))}",
    "storageAccount"    : "${local.storageAccountName}"
	}
	SETTINGS
	protected_settings = <<SETTINGS
	{
    "storageAccountName": "${local.storageAccountName}",
		"storageAccountKey" : "${var.diag_storage_account_access_key}",
		"storageAccountEndpoint" : "${var.diag_storage_account_endpoint}"
	}
	SETTINGS
}

# https://docs.microsoft.com/ko-kr/azure/virtual-machines/extensions/oms-windows 
# https://docs.microsoft.com/ko-kr/azure/virtual-machines/extensions/oms-linux
resource "azurerm_virtual_machine_extension" "monioring" {
  for_each                      = var.log_analytics_workspace_id == null ? {} : { for x in var.instances.vm: x.name => x } 

	name 						              = "OMSExtension" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= azurerm_virtual_machine.vm[each.key].id
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)

	publisher 					          = "Microsoft.EnterpriseCloud.Monitoring"
	type 						              = local.vm_offer == "WindowsServer" ? "MicrosoftMonitoringAgent" : "OmsAgentForLinux"
	type_handler_version 		      = local.vm_offer == "WindowsServer" ? "1.0" : "1.7"
	auto_upgrade_minor_version 	  = true

	settings = <<SETTINGS
	{
		"workspaceId"               : "${var.log_analytics_workspace_id}"
	}
	SETTINGS
	protected_settings = <<PROTECTED_SETTINGS
	{
		"workspaceKey"              : "${var.log_analytics_workspace_key}"
	}
	PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "network_watcher" {
  for_each                      = var.enable_network_watcher_extension == true ? { for x in var.instances.vm: x.name => x } : {}

	name 						              = "Microsoft.Azure.NetworkWatcher" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= azurerm_virtual_machine.vm[each.key].id
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Azure.NetworkWatcher"
	type 						              = local.vm_offer == "WindowsServer" ? "NetworkWatcherAgentWindows" : "NetworkWatcherAgentLinux"
	type_handler_version 		      = "1.4"
	auto_upgrade_minor_version 	  = true
}

resource "azurerm_virtual_machine_extension" "dependency_agent" {
  for_each                      = var.enable_dependency_agent == true ? { for x in var.instances.vm: x.name => x } : {}
	
	name 						              = "DependencyAgentWindows" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= azurerm_virtual_machine.vm[each.key].id
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Azure.Monitoring.DependencyAgent"
	type 						              = local.vm_offer == "WindowsServer" ? "DependencyAgentWindows" : "DependencyAgentLinux"
	type_handler_version 		      = "9.5"
	auto_upgrade_minor_version 	  = true
}

resource "azurerm_virtual_machine_extension" "aadlogin" {
    for_each                      = var.enable_aadlogin == true ? { for x in var.instances.vm: x.name => x } : {}
    
    name                          = "ext-aadlogin"
	  virtual_machine_id						= azurerm_virtual_machine.vm[each.key].id
    
    publisher                     = "Microsoft.Azure.ActiveDirectory"
    type                          = "AADLoginForWindows"
    type_handler_version          = "0.3"
    auto_upgrade_minor_version    = true
}

/*
resource "azurerm_virtual_machine_extension" "iis" {
	count					                = var.custom_script_path == "" ? 0 : local.vm_num
	
	name 						              = "CustomScriptExtension"
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Compute"
	type 						              = "CustomScriptExtension"
	type_handler_version 		      = "1.8"
	auto_upgrade_minor_version 	  = true

	settings = <<SETTINGS
  {
    "fileUris"                  : [
			"https://ebaykrtfbackend.blob.core.windows.net/scripts/install_iis.ps1"
		],
		"commandToExecute"          : "powershell -ExecutionPolicy Unrestricted -File \"install_iis.ps1\""
  }
	SETTINGS
}


resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "association2" {
  for_each                  = var.backend_address_pool_id2 == null ? {} : { for x in var.instances.vm: x.name => x } 
	
	network_interface_id      = azurerm_network_interface.nic[each.key].id
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_address_pool_id2
}

output "vm_map" {
	value = azurerm_virtual_machine.vm
}
*/
