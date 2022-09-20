
resource "azurerm_lb" "lb" {
  lifecycle {
    ignore_changes = [ # don't change existing tags
      tags,
    ]
  }
	
  count                 = var.load_balancer_param == null ? 0 : (local.subnet_ip_offset == 0 ? 0 : 1)
	
  name		              = "${var.name}-lb"
  location              = var.location
	resource_group_name  	= var.resource_group_name

  sku = var.load_balancer_param.sku
    
  frontend_ip_configuration {
    name                          = "lb-frontend-ip"
    subnet_id                     = var.subnet_id
    private_ip_address            = local.subnet_ip_offset == null ? null : cidrhost(var.subnet_prefix, local.subnet_ip_offset)
    private_ip_address_allocation = local.subnet_ip_offset == null ? "dynamic" : "static"

#   it will be zone-redundant frontend ip when zones are not specified.
#    zones = var.use_availability_zone == true ? ["1", "2", "3"] : null
  }

  tags = var.tags_lb
}

resource "azurerm_lb_probe" "probe" {
  count                 = var.load_balancer_param == null ? 0 : (local.subnet_ip_offset == 0 ? 0 : 1)

  resource_group_name   = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id       = azurerm_lb.lb.0.id
  name                  = "${azurerm_lb.lb.0.name}-probe"
  protocol              = var.load_balancer_param.probe_protocol
  port                  = var.load_balancer_param.probe_port

  interval_in_seconds   = var.load_balancer_param.probe_interval
  number_of_probes      = var.load_balancer_param.probe_num
}

resource "azurerm_lb_backend_address_pool" "lb" {
  count                 = var.load_balancer_param == null ? 0 : (local.subnet_ip_offset == 0 ? 0 : 1)

  resource_group_name   = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id       = azurerm_lb.lb.0.id
  name                  = "backendpool"
}

resource "azurerm_lb_rule" "https" {
  lifecycle {
    ignore_changes = [ # don't recreate existing disk
      probe_id
		]
  }

  count                 = var.load_balancer_param == null ? 0 : (local.subnet_ip_offset == 0 ? 0 : 1)

  resource_group_name             = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id                 = azurerm_lb.lb.0.id

	name		                        = "https"
    
  protocol                        = "Tcp"
  frontend_port                   = 443
  backend_port                    = 443

  frontend_ip_configuration_name  = "lb-frontend-ip"
    
	backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
  probe_id                        = azurerm_lb_probe.probe.0.id
  depends_on                      = [azurerm_lb_probe.probe]

  enable_floating_ip              = false # must be false when used for internal load balancing
	idle_timeout_in_minutes         = 4
	load_distribution               = "Default"
	disable_outbound_snat           = false
}

resource "azurerm_lb_rule" "http" {
  count                 = var.load_balancer_param == null ? 0 : (local.subnet_ip_offset == 0 ? 0 : 1)
  
  resource_group_name             = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id                 = azurerm_lb.lb.0.id

	name		                        = "http"
 
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
    
  frontend_ip_configuration_name  = "lb-frontend-ip"
    
  backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
  probe_id                        = azurerm_lb_probe.probe.0.id
  depends_on                      = [azurerm_lb_probe.probe]

  enable_floating_ip              = false # must be false when used for internal load balancing
	idle_timeout_in_minutes         = 4
	load_distribution               = "Default"
	disable_outbound_snat           = false
}

