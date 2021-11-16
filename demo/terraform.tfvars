prefix = "abcd"
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

load_balancer_param = {
  sku             = "standard"
  probe_protocol  = "Tcp" # probe protocol Http, Https, or Tcp
  probe_port      = "3389"  # probe port. (1 ~ 65535)
  probe_interval  = "5"   # probe interval in sec
  probe_num       = "2"   # number of probes

}


