# =============================================================================
# PILOT LIGHT en Azure - Versión simplificada
# =============================================================================
# Esta infraestructura SOLO se despliega cuando AWS cae (failover).
# En operación normal NO existe y no genera coste.
#
# Arquitectura simplificada:
#   - VNet 10.1.0.0/16 con dos subredes
#   - Subred pública (10.1.1.0/24): VM con Docker y Nginx
#   - Subred privada delegada (10.1.2.0/24): Azure DB
#   - VM con IP pública que ejecuta la app y hace de reverse proxy
#
# SKUs ajustados para Azure for Students en Spain Central:
#   - VM: Standard_B2s (2 vCPU, 4 GB RAM)
#   - Azure DB: B_Standard_B1ms sin zone fijada (Azure asigna)
#
# Flujo de tráfico:
#   Usuario → HTTPS (443) → VM (Nginx) → HTTP (localhost:80) → Docker → Azure DB
#
# Backend de Terraform:
#   - Almacenado en Azure Storage (contenedor tfstate)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Estado remoto en Azure Storage (independiente de AWS)
  backend "azurerm" {
    resource_group_name  = "tfg-final-spain-rg"
    storage_account_name = "stgalvarospain2026"
    container_name       = "tfstate"
    key                  = "azure-pilot.terraform.tfstate"
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
  description = "Contraseña del usuario admin de la VM"
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

# Subred pública: VM con Docker
resource "azurerm_subnet" "vm" {
  name                 = "tfg-pilot-subnet-vm"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Subred privada delegada para Azure DB
resource "azurerm_subnet" "mysql" {
  name                 = "tfg-pilot-subnet-mysql"
  resource_group_name  = data.azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr.name
  address_prefixes     = ["10.1.2.0/24"]

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
# NETWORK SECURITY GROUP
# =============================================================================

resource "azurerm_network_security_group" "vm" {
  name                = "tfg-pilot-nsg-vm"
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

  security_rule {
    name                       = "HTTP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Project = "TFG-MultiCloud" }
}

# =============================================================================
# VM CON DOCKER (IP pública)
# =============================================================================

resource "azurerm_public_ip" "vm" {
  name                = "tfg-pilot-vm-ip"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Project = "TFG-MultiCloud" }
}

resource "azurerm_network_interface" "vm" {
  name                = "tfg-pilot-vm-nic"
  location            = data.azurerm_resource_group.dr.location
  resource_group_name = data.azurerm_resource_group.dr.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_linux_virtual_machine" "app" {
  name                = "tfg-pilot-app"
  resource_group_name = data.azurerm_resource_group.dr.name
  location            = data.azurerm_resource_group.dr.location
  # SKU ajustado: Standard_B2s (2 vCPU, 4 GB RAM) tiene mayor disponibilidad
  # en Spain Central para cuentas Azure for Students que Standard_B1ms
  size                = "Standard_B2s"

  admin_username                  = "azureuser"
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.vm.id]

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

  # cloud-init: instala Docker, Nginx y mysql-client
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - docker.io
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
                  proxy_pass http://localhost:80;
                  proxy_set_header Host $$host;
                  proxy_set_header X-Real-IP $$remote_addr;
                  proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $$scheme;
              }
          }
          server {
              listen 8080;
              server_name _;
              return 301 https://$$host$$request_uri;
          }
    runcmd:
      - mkdir -p /etc/nginx/ssl
      - openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/C=ES/ST=Madrid/L=Madrid/O=TFG/CN=tfg-pilot"
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker azureuser
      - systemctl enable nginx
      - systemctl restart nginx
      - echo "OK" > /tmp/vm-ready
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
  # NOTA: la zone se elimina deliberadamente. Spain Central no expone
  # todas las zonas de disponibilidad para Flexible Server con cuentas
  # Azure for Students. Sin "zone" Azure asigna automáticamente la zona
  # disponible en ese momento.

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

  # Permitir cambios futuros de zona sin recrear el recurso
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_mysql_flexible_database" "app" {
  name                = "gym"
  resource_group_name = data.azurerm_resource_group.dr.name
  server_name         = azurerm_mysql_flexible_server.dr.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Desactivar SSL obligatorio
resource "azurerm_mysql_flexible_server_configuration" "disable_ssl" {
  name                = "require_secure_transport"
  resource_group_name = data.azurerm_resource_group.dr.name
  server_name         = azurerm_mysql_flexible_server.dr.name
  value               = "OFF"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "vm_public_ip" {
  description = "IP pública de la VM (acceso SSH y HTTPS de usuarios)"
  value       = azurerm_public_ip.vm.ip_address
}

output "mysql_fqdn" {
  description = "FQDN privado de Azure DB"
  value       = azurerm_mysql_flexible_server.dr.fqdn
}

output "resource_group" {
  description = "Resource group del pilot light"
  value       = data.azurerm_resource_group.dr.name
}
