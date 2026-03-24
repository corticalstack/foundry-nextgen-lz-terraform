# Tests for Phase 2: private DNS zones and VNet links.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# ---------------------------------------------------------------------------
# 1. No DNS zones when flag is false
# ---------------------------------------------------------------------------
run "no_dns_zones_when_flag_false" {
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
    condition     = !can(azurerm_private_dns_zone.dns_zone_cognitive_services[0].name)
    error_message = "Expected no cognitive_services DNS zone when flag is false"
  }

  assert {
    condition     = !can(azurerm_private_dns_zone.dns_zone_openai[0].name)
    error_message = "Expected no openai DNS zone when flag is false"
  }

  assert {
    condition     = !can(azurerm_private_dns_zone.dns_zone_apim[0].name)
    error_message = "Expected no apim DNS zone when flag is false"
  }
}

# ---------------------------------------------------------------------------
# Shared private_networking value used by tests 2-4
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 2. Exactly 8 DNS zones exist when flag is true
# ---------------------------------------------------------------------------
run "eight_dns_zones_when_flag_true" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
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
    condition     = can(azurerm_private_dns_zone.dns_zone_cognitive_services[0].name)
    error_message = "Expected cognitive_services DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_openai[0].name)
    error_message = "Expected openai DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_services_ai[0].name)
    error_message = "Expected services_ai DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_search[0].name)
    error_message = "Expected search DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_documents[0].name)
    error_message = "Expected documents DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_blob[0].name)
    error_message = "Expected blob DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_file[0].name)
    error_message = "Expected file DNS zone to exist"
  }

  assert {
    condition     = can(azurerm_private_dns_zone.dns_zone_apim[0].name)
    error_message = "Expected apim DNS zone to exist"
  }
}

# ---------------------------------------------------------------------------
# 3. All 8 VNet links have registration_enabled = false
# ---------------------------------------------------------------------------
run "eight_vnet_links_when_flag_true" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
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
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_cognitive_services[0].registration_enabled == false
    error_message = "cognitive_services VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_openai[0].registration_enabled == false
    error_message = "openai VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_services_ai[0].registration_enabled == false
    error_message = "services_ai VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_search[0].registration_enabled == false
    error_message = "search VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_documents[0].registration_enabled == false
    error_message = "documents VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_blob[0].registration_enabled == false
    error_message = "blob VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_file[0].registration_enabled == false
    error_message = "file VNet link must have registration_enabled = false"
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.vnet_link_apim[0].registration_enabled == false
    error_message = "apim VNet link must have registration_enabled = false"
  }
}

# ---------------------------------------------------------------------------
# 4. All zone names match the authoritative list exactly
# ---------------------------------------------------------------------------
run "all_zone_names_match_authoritative_list" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
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
    condition     = azurerm_private_dns_zone.dns_zone_cognitive_services[0].name == "privatelink.cognitiveservices.azure.com"
    error_message = "cognitive_services zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_openai[0].name == "privatelink.openai.azure.com"
    error_message = "openai zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_services_ai[0].name == "privatelink.services.ai.azure.com"
    error_message = "services_ai zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_search[0].name == "privatelink.search.windows.net"
    error_message = "search zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_documents[0].name == "privatelink.documents.azure.com"
    error_message = "documents zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_blob[0].name == "privatelink.blob.core.windows.net"
    error_message = "blob zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_file[0].name == "privatelink.file.core.windows.net"
    error_message = "file zone name mismatch"
  }

  assert {
    condition     = azurerm_private_dns_zone.dns_zone_apim[0].name == "privatelink.azure-api.net"
    error_message = "apim zone name mismatch"
  }
}
