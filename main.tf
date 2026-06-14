# Resource Group — the container for every lab resource
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network — 10.0.0.0/16 private network for all three VMs
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

# Pause 45s — Azure sometimes lags after creating a VNet
resource "time_sleep" "wait_after_vnet" {
  create_duration = "45s"
  depends_on      = [azurerm_virtual_network.vnet]
}
# Subnet — 10.0.1.0/24 carved from the VNet; all three VMs live here
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
  depends_on           = [time_sleep.wait_after_vnet]
}

# NSG — firewall that allows RDP (port 3389) only from your IP
resource "azurerm_network_security_group" "nsg" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP-3389"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.rdp_source
    source_port_range          = "*"
    destination_port_range     = "3389"
    destination_address_prefix = "*"
  }
  depends_on = [time_sleep.wait_after_vnet]
}

# Pause 45s — same consistency safeguard, now after the NSG
resource "time_sleep" "wait_after_nsg" {
  create_duration = "45s"
  depends_on      = [azurerm_network_security_group.nsg]
}
# Public IPs — one per VM, so you can RDP in from your machine
resource "azurerm_public_ip" "dc01" {
  name                = "dc01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}
resource "azurerm_public_ip" "fs01" {
  name                = "fs01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}
resource "azurerm_public_ip" "client01" {
  name                = "client01-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on          = [time_sleep.wait_after_nsg]
}

# DC01 NIC — STATIC private IP 10.0.1.4 so DNS never breaks
resource "azurerm_network_interface" "dc01" {
  name                = "dc01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.dc01.id
  }
  depends_on = [time_sleep.wait_after_nsg]
}

# FS01 NIC — dynamic private IP is fine; it's not a DNS server
resource "azurerm_network_interface" "fs01" {
  name                = "fs01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fs01.id
  }
  depends_on = [time_sleep.wait_after_nsg, azurerm_network_interface.dc01]
}

# CLIENT01 NIC — dynamic private IP
resource "azurerm_network_interface" "client01" {
  name                = "client01-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client01.id
  }
  depends_on = [time_sleep.wait_after_nsg, azurerm_network_interface.dc01]
}
# Attach the NSG to each NIC — without this the firewall protects nothing
resource "azurerm_network_interface_security_group_association" "dc01" {
  network_interface_id      = azurerm_network_interface.dc01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}
resource "azurerm_network_interface_security_group_association" "fs01" {
  network_interface_id      = azurerm_network_interface.fs01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}
resource "azurerm_network_interface_security_group_association" "client01" {
  network_interface_id      = azurerm_network_interface.client01.id
  network_security_group_id = azurerm_network_security_group.nsg.id
  depends_on                = [time_sleep.wait_after_nsg]
}

# DC01 — Windows Server 2022, becomes the Domain Controller
resource "azurerm_windows_virtual_machine" "dc01" {
  name                  = "DC01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.server_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc01.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  depends_on = [time_sleep.wait_after_nsg]
}

# FS01 — Windows Server 2022, the File Server
resource "azurerm_windows_virtual_machine" "fs01" {
  name                  = "FS01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.server_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.fs01.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  depends_on = [time_sleep.wait_after_nsg]
}

# CLIENT01 — Windows 11 Pro, the test workstation
resource "azurerm_windows_virtual_machine" "client01" {
  name                  = "CLIENT01"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.client_vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.client01.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }
  depends_on = [time_sleep.wait_after_nsg]
}
# Enable RDP on CLIENT01 — Windows 11 ships with it disabled.
# Flips the registry switch and opens the firewall rule at the OS level.
resource "azurerm_virtual_machine_extension" "client01_enable_rdp" {
  name                 = "enable-rdp"
  virtual_machine_id   = azurerm_windows_virtual_machine.client01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  settings = jsonencode({
    commandToExecute = "powershell -Command \"Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0; Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'\""
  })
  depends_on = [azurerm_windows_virtual_machine.client01]
}