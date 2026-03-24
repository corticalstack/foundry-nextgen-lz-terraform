# Tests for Phase 6: Azure Bastion and jump VM.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared variable blocks — flag false (public mode)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. No Bastion when flag is false
# ---------------------------------------------------------------------------
run "no_bastion_when_flag_false" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = false
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = !can(azurerm_bastion_host.main[0].id)
    error_message = "Expected no Bastion host when enable_private_networking = false"
  }

  assert {
    condition     = !can(azurerm_public_ip.bastion[0].id)
    error_message = "Expected no Bastion public IP when enable_private_networking = false"
  }
}

# ---------------------------------------------------------------------------
# 2. No jump VM when flag is false
# ---------------------------------------------------------------------------
run "no_jump_vm_when_flag_false" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = false
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = !can(azurerm_windows_virtual_machine.jump_vm[0].id)
    error_message = "Expected no jump VM when enable_private_networking = false"
  }

  assert {
    condition     = !can(azurerm_network_interface.jump_vm[0].id)
    error_message = "Expected no jump VM NIC when enable_private_networking = false"
  }
}

# ---------------------------------------------------------------------------
# Shared private_networking value used by tests 3-8
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 3. Bastion SKU is Basic
# ---------------------------------------------------------------------------
run "bastion_sku_is_basic" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_bastion_host.main[0].sku == "Basic"
    error_message = "Bastion SKU must be Basic"
  }
}

# ---------------------------------------------------------------------------
# 4. Jump VM NIC has no public IP
# ---------------------------------------------------------------------------
run "jump_vm_has_no_public_ip" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_network_interface.jump_vm[0].ip_configuration[0].public_ip_address_id == null
    error_message = "Jump VM NIC must not have a public IP address"
  }
}

# ---------------------------------------------------------------------------
# 5. Jump VM OS is Windows Server 2022 Datacenter Gen2
# ---------------------------------------------------------------------------
run "jump_vm_os_is_windows_server_2022" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_windows_virtual_machine.jump_vm[0].source_image_reference[0].publisher == "MicrosoftWindowsServer"
    error_message = "Jump VM publisher must be MicrosoftWindowsServer"
  }

  assert {
    condition     = azurerm_windows_virtual_machine.jump_vm[0].source_image_reference[0].offer == "WindowsServer"
    error_message = "Jump VM offer must be WindowsServer"
  }

  assert {
    condition     = azurerm_windows_virtual_machine.jump_vm[0].source_image_reference[0].sku == "2022-datacenter-g2"
    error_message = "Jump VM SKU must be 2022-datacenter-g2 (Windows Server 2022 Datacenter Gen2)"
  }
}

# ---------------------------------------------------------------------------
# 6. Jump VM size is Standard_B2s
# ---------------------------------------------------------------------------
run "jump_vm_size_is_b2s" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_windows_virtual_machine.jump_vm[0].size == "Standard_B2s"
    error_message = "Jump VM size must be Standard_B2s"
  }
}

# ---------------------------------------------------------------------------
# 7. Auto-shutdown schedule exists when flag is true
# ---------------------------------------------------------------------------
run "auto_shutdown_exists" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_dev_test_global_vm_shutdown_schedule.jump_vm[0].daily_recurrence_time == "1900"
    error_message = "Auto-shutdown must be scheduled at 1900"
  }

  assert {
    condition     = azurerm_dev_test_global_vm_shutdown_schedule.jump_vm[0].timezone == "UTC"
    error_message = "Auto-shutdown timezone must be UTC"
  }
}

# ---------------------------------------------------------------------------
# 8. Bastion uses the bastion_subnet_id from private_networking variable
# ---------------------------------------------------------------------------
run "bastion_uses_bastion_subnet" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_bastion_host.main[0].ip_configuration[0].subnet_id == var.private_networking.bastion_subnet_id
    error_message = "Bastion must use var.private_networking.bastion_subnet_id"
  }
}
