# Configure azure provider

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.31.1"

    }
  }
}

# Provides configuration details for the Azure Terraform provider

provider "azurerm" {
  features {}
}

# Provides the Resource Group to Logically contain resources
resource "azurerm_resource_group" "rg" {
  name     = "RessourceGroupEspecializacao"
  location = "southcentralus"
  tags = {
    environment = "dev"
    source      = "Terraform"

  }
}


#Create a virtual Network
resource "azurerm_virtual_network" "vnet" {
  name = "vn-terraform"
  address_space = ["10.1.0.0/16"]
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
} 

#Create a subnet 
resource "azurerm_subnet" "subnet" {
  name = "internal"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}  

# Provides a public IP
resource "azurerm_public_ip" "public_ip" {
  name                = "vm01-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
#  domain_name_label   = random_string.fqdn.result
}
 
# Create NGS
resource "azurerm_network_security_group" "nsg"{
  name = "vm01-nsg01"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  security_rule {
    access = "Allow"
    destination_address_prefix = "*"
    destination_port_range = "22"
    direction = "Inbound"
    name = "SSH"
    priority = "1001"
    protocol = "Tcp"
    source_address_prefix = "*"
    source_port_range = "*"
  } 
}

#Create network interface
#resource "azurerm_network_interface" "nic"{
#  name = "vm01-nic"
#  location = azurerm_resource_group.rg.location
#  resource_group_name = azurerm_resource_group.rg.name
#  ip_configuration {
#    name = "vm01-nic-config"
#    subnet_id = azurerm_subnet.subnet.id
#    private_ip_address_allocation = "dynamic" 
#    public_ip_address_id = azurerm_public_ip.public_ip.id
#
#  }
#}

#Create load balancer
resource "azurerm_lb" "lb" {
  name                = "wp-loadbalancer"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
 resource_group_name = azurerm_resource_group.rg.name
 loadbalancer_id     = azurerm_lb.lb.id
 name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "lb_pb" {
 resource_group_name = azurerm_resource_group.rg.name
 loadbalancer_id     = azurerm_lb.lb.id
 name                = "http-running-probe"
 port                = 80
}

resource "azurerm_lb_rule" "lb_rule" {
 resource_group_name = azurerm_resource_group.rg.name
 loadbalancer_id     = azurerm_lb.lb.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = 80
   backend_port                   = 80
   backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = azurerm_lb_probe.lb_pb.id
}


# Create MySQL Server
resource "azurerm_mysql_server" "mysql_server" {
  resource_group_name = azurerm_resource_group.rg.name
  name = "vm-mysql-server"
  location = azurerm_resource_group.rg.location
  version = "5.7"

  
  administrator_login = "adminMySql"
  administrator_login_password = "SenhaMySql123!"

  sku_name = "B_Gen5_2"
  storage_mb = "5120"
  auto_grow_enabled = false
  backup_retention_days = 7
  geo_redundant_backup_enabled = false

  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled = false
}

# Config MySQL Server Firewall Rule
resource "azurerm_mysql_firewall_rule" "mysql_firewall" {
  name                = "vm-mysql-firewall-rule"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.mysql_server.name
  start_ip_address    = azurerm_public_ip.public_ip.ip_address
  end_ip_address      = azurerm_public_ip.public_ip.ip_address
}

# Create MySql DataBase
resource "azurerm_mysql_database" "mysql_db" {
  name                = "vm-mysql-db"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.mysql_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}


data "template_file" "script" {
  template = file("cloud-init.conf")
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "cloud-init.conf"
    content_type = "text/cloud-config"
    content      = data.template_file.script.rendered
  }
  depends_on = [azurerm_mysql_server.mysql_server]
}


# Create virtual machine scale

resource "azurerm_linux_virtual_machine_scale_set" "vm" {
  name = "vm01"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                             = "Standard_F2"
  instances                       = 2
  admin_username                  = "admin123"
  admin_password                  = "Senha123!"
  disable_password_authentication = false
  custom_data                     = data.template_cloudinit_config.config.rendered

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                      = "networkinterface"
    primary                   = true

    ip_configuration {
      name                                   = "IPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
    }
  }
}

 