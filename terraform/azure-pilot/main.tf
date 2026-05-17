# =============================================================================
# PILOT LIGHT en Azure - Arquitectura simétrica a AWS
# =============================================================================
# Esta infraestructura SOLO se despliega cuando AWS cae (failover).
# En operación normal NO existe y no genera coste.
#
# Arquitectura (igual que AWS):
#   - VNet 10.1.0.0/16 con tres subredes
#   - Subred pública (10.1.1.0/24): Bastion Host con Nginx reverse proxy
#   - Subred privada de app (10.1.11.0/24): VM Docker con la app PHP
#   - Subred privada de datos (10.1.12.0/24): Azure DB delegada
#   - NAT Gateway para salida de la VM privada
#   - Private DNS Zone para que la VM resuelva el FQDN privado de Azure DB
#
# Flujo de tráfico (idéntico a AWS):
#   Usuario → HTTPS (443) → Bastion (Nginx) → HTTP (80) → VM Docker → Azure DB
#
# Recursos creados:
#   - VNet + 3 subredes + NAT Gateway + Public IP NAT
#   - NSG bastion, NSG VM, NSG MySQL
#   - Bastion Host (Standard_B1s) con IP pública estática
#   - VM Docker (Standard_B1ms) sin IP pública
#   - Azure DB for MySQL Flexible Server (B_Standard_B1ms)
#   - Private DNS Zone para Azure DB
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Estado remoto en S3 (mismo bucket que AWS, ya configurado)
  backend "s3" {
    key    = "azure-pilot/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "db_password" {
  description = "Contraseña del usuario admin de Azure DB"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "La contraseña debe tener al menos 8 caracteres."
  }
}

variable "vm_admin_password" {
  description = "Contraseña del usuario admin de las VMs (bastión y app)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vm_admin_password) >= 12
    error_message = "Azure exige al menos 12 caracteres en la contraseña de VM."
  }
}

# =============================================================================
# RESOURCE GROUP (creado previamente por setup-azure-blob.yml)
# =============================================================================

data "azurerm_resource_group" "dr" {
  name = "tfg-final-spain-rg"
}

# =============================================================================
# RED: VNet y subredes
# =============================================================================

resource "azurerm_virtual_network" "dr" {
  name                = "tfg-pilot-vnet"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  address_space       = ["10.1.0.0/16"]

  tags = { Project = "TFG-MultiCloud" }
}

# Subred pública: bastión
resource "azurerm_subnet" "public" {
  name                 = "tfg-pilot-subnet-public"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Subred privada: VM Docker con la app
resource "azurerm_subnet" "private_app" {
  name                 = "tfg-pilot-subnet-private-app"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.11.0/24"]
}

# Subred privada delegada para Azure DB
resource "azurerm_subnet" "mysql" {
  name                 = "tfg-pilot-subnet-mysql"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.12.0/24"]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# =============================================================================
# NAT GATEWAY: permite que la VM privada salga a internet
# =============================================================================

resource "azurerm_public_ip" "nat" {
  name                = "tfg-pilot-nat-ip"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_nat_gateway" "dr" {
  name                = "tfg-pilot-nat-gw"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  sku_name            = "Standard"

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_nat_gateway_public_ip_association" "dr" {
  nat_gateway_id       = azurerm_nat_gateway.dr.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Asociar NAT Gateway a la subred privada de la app
resource "azurerm_subnet_nat_gateway_association" "private_app" {
  subnet_id      = azurerm_subnet.private_app.id
  nat_gateway_id = azurerm_nat_gateway.dr.id
}

# =============================================================================
# PRIVATE DNS ZONE: para que la VM resuelva el FQDN de Azure DB
# =============================================================================

resource "azurerm_private_dns_zone" "mysql" {
  name                = "alvaro-tfg.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.dr.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "tfg-pilot-dns-link"
  resource_group_name   = data.azurerm_resource_group.dr.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.dr.id
}

# =============================================================================
# NETWORK SECURITY GROUPS
# =============================================================================

# NSG del Bastión: SSH y HTTPS desde internet
resource "azurerm_network_security_group" "bastion" {
  name                = "tfg-pilot-nsg-bastion"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Project = "TFG-MultiCloud" }
}

# NSG de la VM Docker: HTTP y SSH solo desde el bastión
resource "azurerm_network_security_group" "app" {
  name                = "tfg-pilot-nsg-app"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  security_rule {
    name                       = "HTTP-from-bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.1.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH-from-bastion"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.1.1.0/24"
    destination_address_prefix = "*"
  }

  tags = { Project = "TFG-MultiCloud" }
}

# =============================================================================
# BASTION HOST (subred pública)
# =============================================================================

resource "azurerm_public_ip" "bastion" {
  name                = "tfg-pilot-bastion-ip"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_network_interface" "bastion" {
  name                = "tfg-pilot-bastion-nic"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_network_interface_security_group_association" "bastion" {
  network_interface_id      = azurerm_network_interface.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_linux_virtual_machine" "bastion" {
  name                = "tfg-pilot-bastion"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location
  size                = "Standard_B1s"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.bastion.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # cloud-init: instala Nginx, mysql-client y genera certificado SSL
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - nginx
      - mysql-client
      - openssl
    write_files:
      - path: /etc/nginx/sites-available/default
        content: |
          server {
              listen 443 ssl;
              server_name _;

              ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
              ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

              location / {
                  proxy_pass http://PLACEHOLDER_APP_IP:80;
                  proxy_set_header Host $$host;
                  proxy_set_header X-Real-IP $$remote_addr;
                  proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $$scheme;
              }
          }
          server {
              listen 80;
              server_name _;
              return 301 https://$$host$$request_uri;
          }
    runcmd:
      - mkdir -p /etc/nginx/ssl
      - openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/C=ES/ST=Madrid/L=Madrid/O=TFG/CN=tfg-pilot"
      - systemctl enable nginx
      - echo "OK" > /tmp/bastion-ready
  CLOUDINIT
  )

  tags = { Project = "TFG-MultiCloud" }
}

# =============================================================================
# VM DOCKER (subred privada)
# =============================================================================

resource "azurerm_network_interface" "app" {
  name                = "tfg-pilot-app-nic"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_app.id
    private_ip_address_allocation = "Dynamic"
    # Sin IP pública - solo accesible vía bastión
  }
}

resource "azurerm_network_interface_security_group_association" "app" {
  network_interface_id      = azurerm_network_interface.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_linux_virtual_machine" "app" {
  name                = "tfg-pilot-app"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location
  size                = "Standard_B1ms"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.app.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # cloud-init: instala Docker y mysql-client
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - docker.io
      - mysql-client
    runcmd:
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker azureuser
      - echo "OK" > /tmp/app-ready
  CLOUDINIT
  )

  tags = { Project = "TFG-MultiCloud" }
}

# =============================================================================
# AZURE DB FOR MYSQL FLEXIBLE SERVER
# =============================================================================

resource "azurerm_mysql_flexible_server" "dr" {
  name                = "tfg-pilot-mysql-alvaro-2026"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location

  administrator_login    = "admin_tfg"
  administrator_password = var.db_password

  sku_name = "B_Standard_B1ms"
  version  = "8.0.21"
  zone     = "2"

  storage {
    size_gb = 20
    iops    = 360
  }

  delegated_subnet_id = azurerm_subnet.mysql.id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = { Project = "TFG-MultiCloud" }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

resource "azurerm_mysql_flexible_database" "app" {
  name                = "gym"
  resource_group_name = data.azurerm_resource_group.dr.name
  server_name         = azurerm_mysql_flexible_server.dr.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Desactivar SSL obligatorio (mismo comportamiento que RDS en AWS)
resource "azurerm_mysql_flexible_server_configuration" "disable_ssl" {
  name                = "require_secure_transport"
  resource_group_name = data.azurerm_resource_group.dr.name
  server_name         = azurerm_mysql_flexible_server.dr.name
  value               = "OFF"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "bastion_public_ip" {
  description = "IP pública del bastión Azure (acceso SSH y HTTPS de usuarios)"
  value       = azurerm_public_ip.bastion.ip_address
}

output "app_private_ip" {
  description = "IP privada de la VM Docker (para configurar Nginx en el bastión)"
  value       = azurerm_network_interface.app.private_ip_address
}

output "mysql_fqdn" {
  description = "FQDN privado de Azure DB. Solo resoluble desde dentro de la VNet."
  value       = azurerm_mysql_flexible_server.dr.fqdn
}

output "resource_group" {
  description = "Resource group del pilot light"
  value       = data.azurerm_resource_group.dr.name
}

output "nat_gateway_ip" {
  description = "IP pública del NAT Gateway (IP de salida de la VM privada)"
  value       = azurerm_public_ip.nat.ip_address
}
