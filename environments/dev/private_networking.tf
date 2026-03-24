# =============================================================================
# PRIVATE NETWORKING — DNS zones, VNet links, Bastion, Jump VM
#
# All resources in this file are conditional on var.enable_private_networking.
# When false (default), zero resources are created and existing behaviour is
# completely unchanged.
# =============================================================================

# =============================================================================
# MANAGED VNET — created when enable_private_networking = true AND
# private_networking variable is null (default).
# Set private_networking in tfvars to use a pre-existing BYO VNet instead.
# =============================================================================

locals {
  create_vnet = var.enable_private_networking && var.private_networking == null
}

resource "azurerm_virtual_network" "main" {
  count               = local.create_vnet ? 1 : 0
  name                = "vnet-${var.customer}"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  address_space       = var.vnet_config.address_space
  tags                = local.common_tags
}

# snet-pe — private endpoints
# private_endpoint_network_policies must be Disabled for PEs to work.
resource "azurerm_subnet" "pe" {
  count                             = local.create_vnet ? 1 : 0
  name                              = "snet-pe"
  resource_group_name               = module.core.core_rg_name
  virtual_network_name              = azurerm_virtual_network.main[0].name
  address_prefixes                  = [var.vnet_config.subnet_pe]
  private_endpoint_network_policies = "Disabled"
}

# snet-agents — Foundry Agent Service VNet injection (Container Apps)
resource "azurerm_subnet" "agents" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-agents"
  resource_group_name  = module.core.core_rg_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.vnet_config.subnet_agents]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# snet-agents-spoke — Foundry Agent Service VNet injection for the spoke account.
# Each AI Services account with networkInjections requires its own dedicated subnet;
# snet-agents is already claimed by the core account.
resource "azurerm_subnet" "agents_spoke" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-agents-spoke"
  resource_group_name  = module.core.core_rg_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.vnet_config.subnet_agents_spoke]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# snet-apim — APIM StandardV2 outbound VNet integration.
# StandardV2 outbound integration requires Microsoft.Web/serverFarms delegation
# (NOT Microsoft.ApiManagement/service — that is for Premium VNet injection).
# See: https://aka.ms/apim-vnet-outbound
resource "azurerm_subnet" "apim" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-apim"
  resource_group_name  = module.core.core_rg_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.vnet_config.subnet_apim]

  delegation {
    name = "Microsoft.Web.serverFarms"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }

  lifecycle {
    ignore_changes = [delegation[0].service_delegation[0].actions]
  }
}

# NAT gateway — provides outbound internet access for the jump VM.
# The jump VM has no public IP so Azure's default outbound SNAT is unavailable;
# a NAT gateway is required for the browser on the jump VM to reach ai.azure.com.
resource "azurerm_public_ip" "nat" {
  count               = local.create_vnet ? 1 : 0
  name                = "pip-nat"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "main" {
  count               = local.create_vnet ? 1 : 0
  name                = "nat-${var.customer}"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count                = local.create_vnet ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# snet-jump — jump VM NIC
resource "azurerm_subnet" "jump" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-jump"
  resource_group_name  = module.core.core_rg_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.vnet_config.subnet_jump]
}

resource "azurerm_subnet_nat_gateway_association" "jump" {
  count          = local.create_vnet ? 1 : 0
  subnet_id      = azurerm_subnet.jump[0].id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}

# AzureBastionSubnet — MUST be named exactly this; /26 or larger enforced by Azure.
resource "azurerm_subnet" "bastion" {
  count                = local.create_vnet ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = module.core.core_rg_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.vnet_config.subnet_bastion]
}

# NSG for the jump VM subnet — allows Bastion (VirtualNetwork tag) to reach
# the VM via RDP; denies all other inbound internet traffic.
resource "azurerm_network_security_group" "jump" {
  count               = local.create_vnet ? 1 : 0
  name                = "nsg-jump"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowBastionRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "jump" {
  count                     = local.create_vnet ? 1 : 0
  subnet_id                 = azurerm_subnet.jump[0].id
  network_security_group_id = azurerm_network_security_group.jump[0].id
}

# =============================================================================
# PRIVATE DNS ZONES — created in the hub resource group
# registration_enabled = false is REQUIRED; true causes zone delegation failures.
# =============================================================================

resource "azurerm_private_dns_zone" "dns_zone_cognitive_services" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_openai" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.openai.azure.com"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_services_ai" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.services.ai.azure.com"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_search" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.search.windows.net"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_documents" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.documents.azure.com"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_blob" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_file" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "dns_zone_apim" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.azure-api.net"
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags
}

# =============================================================================
# VNET LINKS — link each DNS zone to the BYO VNet
# registration_enabled = false is REQUIRED; true causes failures.
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_cognitive_services" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-cognitive-services"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_cognitive_services[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_cognitive_services]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_openai" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-openai"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_openai[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_openai]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_services_ai" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-services-ai"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_services_ai[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_services_ai]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_search" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-search"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_search[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_search]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_documents" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-documents"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_documents[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_documents]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_blob" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-blob"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_blob[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_blob]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_file" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-file"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_file[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_file]
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link_apim" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "link-apim"
  resource_group_name   = module.core.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone_apim[0].name
  virtual_network_id    = local.private_networking_effective.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
  depends_on            = [azurerm_private_dns_zone.dns_zone_apim]
}

# =============================================================================
# DNS ZONE IDS LOCAL — passed to hub and spoke-multi modules
# =============================================================================

locals {
  dns_zone_ids = var.enable_private_networking ? {
    cognitive_services = azurerm_private_dns_zone.dns_zone_cognitive_services[0].id
    openai             = azurerm_private_dns_zone.dns_zone_openai[0].id
    services_ai        = azurerm_private_dns_zone.dns_zone_services_ai[0].id
    search             = azurerm_private_dns_zone.dns_zone_search[0].id
    documents          = azurerm_private_dns_zone.dns_zone_documents[0].id
    blob               = azurerm_private_dns_zone.dns_zone_blob[0].id
    file               = azurerm_private_dns_zone.dns_zone_file[0].id
    apim               = azurerm_private_dns_zone.dns_zone_apim[0].id
  } : null
}

# =============================================================================
# AZURE BASTION — Basic SKU (~£90/month, 25 concurrent sessions)
#
# IMPORTANT: The subnet supplied via var.private_networking.bastion_subnet_id
# MUST be named exactly "AzureBastionSubnet" and be /26 or larger.
# Azure enforces this at the platform level — any other name causes deployment
# failure. Create and name the subnet correctly before running terraform apply.
# =============================================================================

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pip-bastion"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = local.common_tags
}

resource "azurerm_bastion_host" "main" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "bas-${var.customer}"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  sku                 = "Basic"
  tags                = local.common_tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = local.private_networking_effective.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  depends_on = [azurerm_public_ip.bastion]
}

# =============================================================================
# JUMP VM — Windows Server 2022 Datacenter Gen2, Standard_B2s, no public IP
# Access via: Azure portal → Bastion → jump VM
# =============================================================================

resource "azurerm_network_interface" "jump_vm" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "nic-jump-vm"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.private_networking_effective.jump_vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = null
  }
}

resource "azurerm_windows_virtual_machine" "jump_vm" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "vm-jump"
  location            = var.location
  resource_group_name = module.core.core_rg_name
  size                = "Standard_B2s"
  admin_username      = var.jump_vm_admin_username
  admin_password      = var.jump_vm_admin_password
  tags                = local.common_tags

  network_interface_ids = [azurerm_network_interface.jump_vm[0].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_network_interface.jump_vm]
}

resource "azurerm_virtual_machine_extension" "jump_vm_setup" {
  count                      = var.enable_private_networking ? 1 : 0
  name                       = "install-tools"
  virtual_machine_id         = azurerm_windows_virtual_machine.jump_vm[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = join(" && ", [
      # Azure CLI
      "powershell -Command \"Invoke-WebRequest -Uri 'https://aka.ms/installazurecliwindows' -OutFile AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; Remove-Item AzureCLI.msi\"",
      # PowerShell 7
      "powershell -Command \"Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi' -OutFile PS7.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I PS7.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 REGISTER_MANIFEST=1'; Remove-Item PS7.msi\"",
      # Terraform (via winget; falls back gracefully if winget unavailable)
      "powershell -Command \"winget install --id Hashicorp.Terraform -e --accept-source-agreements --accept-package-agreements 2>$null; exit 0\""
    ])
  })

  depends_on = [azurerm_windows_virtual_machine.jump_vm]
}

# =============================================================================
# AUTO-SHUTDOWN — shuts the jump VM down at 19:00 UTC to reduce idle cost
# =============================================================================

resource "azurerm_dev_test_global_vm_shutdown_schedule" "jump_vm" {
  count              = var.enable_private_networking ? 1 : 0
  virtual_machine_id = azurerm_windows_virtual_machine.jump_vm[0].id
  location           = var.location
  enabled            = true

  daily_recurrence_time = "2300"
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }

  depends_on = [azurerm_windows_virtual_machine.jump_vm]
}
