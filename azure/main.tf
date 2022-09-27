terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

resource "azurerm_resource_group" "default" {
  name     = "Default"
  location = "West Europe"
}

resource "azurerm_virtual_network" "vn" {
  name                = "Default vnet"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  address_space       = "10.0.0.0/24"
}

resource "azurerm_subnet" "subneta" {
  name                 = "Subnet A"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = "10.0.0.0/28"
}

resource "azurerm_subnet" "subnetb" {
  name                 = "Subnet B"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = "10.0.0.16/28"
}

resource "azurerm_public_ip" "public_ip" {
  name                = "LB public ip"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "loadbalancer" {
  name                = "Load Balancer"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_lb_rule" "lbnatrule" {
   resource_group_name            = azurerm_resource_group.default.name
   loadbalancer_id                = azurerm_lb.loadbalancer.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = 80
   backend_port                   = 80
   backend_address_pool_id        = azurerm_lb_backend_address_pool.bepool.id
   frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_backend_address_pool" "bepool" {
 resource_group_name = azurerm_resource_group.default.name
 loadbalancer_id     = azurerm_lb.loadbalancer.id
 name                = "Backend Pool"
}

resource "azurerm_network_security_group" "security-group" {
  name                = "Security Group for VMs"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_network_security_rule" "http_security_rule" {
  name                        = "HTTP Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.default.name
  network_security_group_name = azurerm_network_security_group.security-group.name
}

resource "azurerm_network_security_rule" "ssh_security_rule" {
  name                        = "SSH Inbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.default.name
  network_security_group_name = azurerm_network_security_group.security-group.name
}

