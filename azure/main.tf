terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}


resource "azurerm_resource_group" "default" {
  name     = "Default"
  location = "West Europe"
}

resource "azurerm_virtual_network" "vn" {
  name                = "Default_vnet"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "internal" {
  name                 = "Subnet-Instance"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = ["10.0.0.0/28"]
}

resource "azurerm_subnet" "internaldb" {
  name                 = "Subnet-DB"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = ["10.0.0.32/28"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "LB_public_ip"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "loadbalancer" {
  name                = "Load_Balancer"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_lb_rule" "lbnatrule" {
   loadbalancer_id                = azurerm_lb.loadbalancer.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = 22
   backend_port                   = 22
   backend_address_pool_ids        = [azurerm_lb_backend_address_pool.bepool.id]
   frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_backend_address_pool" "bepool" {
 loadbalancer_id     = azurerm_lb.loadbalancer.id
 name                = "VMs_Backend_Pool"
}

resource "azurerm_network_interface_backend_address_pool_association" "lb_association" {
  network_interface_id  = "${element(azurerm_network_interface.nic.*.id, count.index)}"
  ip_configuration_name = "ipconfig${count.index}"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.bepool.id
  count                 = 2
}

resource "azurerm_network_security_group" "security-group" {
  name                = "VMs_Security_Group"
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

resource "azurerm_network_interface" "nic" {
  name                = "nic${count.index}"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  count = 2
  ip_configuration {
    name                          = "ipconfig${count.index}"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_availability_set" "default" {
  name                = "default-aset"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "vm${count.index}"
  location              = azurerm_resource_group.default.location
  resource_group_name   = azurerm_resource_group.default.name
  network_interface_ids = ["${element(azurerm_network_interface.nic.*.id, count.index)}"]
  size               = "Standard_B2s"
  count = 2
  availability_set_id = azurerm_availability_set.default.id

  custom_data  = filebase64("user-data.txt")
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  computer_name  = "hostname"
  admin_username = "testadmin"
  admin_password = "Password1234!"
  disable_password_authentication = false

}

resource "azurerm_mysql_server" "mysqlserver" {
  name                = "mysqldb-server-ippon"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name

  administrator_login          = "foo"
  administrator_login_password = "IpponTechnologies12*"

  sku_name   = "GP_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  auto_grow_enabled                 = false
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = false
  ssl_enforcement_enabled           = false
  ssl_minimal_tls_version_enforced  = "TLSEnforcementDisabled"
}

resource "azurerm_mysql_database" "db" {
  name                = "mysqldb"
  resource_group_name = azurerm_resource_group.default.name
  server_name         = azurerm_mysql_server.mysqlserver.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

resource "azurerm_private_endpoint" "endpoint" {
  name                = "DB-endpoint"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  subnet_id           = azurerm_subnet.internaldb.id

  private_service_connection {
    name                           = "DB-private-connection"
    private_connection_resource_id = azurerm_mysql_server.mysqlserver.id
    subresource_names              = [ "mysqlServer" ]
    is_manual_connection           = false
  }
}
