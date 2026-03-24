# Tests for Phase 3: hub module private networking resources.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared private_networking value used across tests
variables {
  environment               = "dev"
  enable_private_networking = false
  location                  = "swedencentral"
  publisher_email           = "test@example.com"
  publisher_name            = "Test"
  deployer_principal_id     = "00000000-0000-0000-0000-000000000001"
  teams                     = ["alpha"]
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

# ---------------------------------------------------------------------------
# 1. No private endpoints when flag is false
# ---------------------------------------------------------------------------
run "no_private_endpoints_when_flag_false" {
  command = plan

  variables {
    enable_private_networking = false
  }

  assert {
    condition     = !can(azurerm_private_endpoint.hub_account[0].id)
    error_message = "Expected no hub account PE when flag is false"
  }

  assert {
    condition     = !can(azurerm_private_endpoint.research_account[0].id)
    error_message = "Expected no research account PE when flag is false"
  }

  assert {
    condition     = !can(azurerm_private_endpoint.apim[0].id)
    error_message = "Expected no APIM PE when flag is false"
  }
}

# ---------------------------------------------------------------------------
# 2. Two account private endpoints when flag is true
# ---------------------------------------------------------------------------
run "two_account_endpoints_when_flag_true" {
  command = plan

  variables {
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    dns_zone_ids = {
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.hub_account[0].private_service_connection[0].subresource_names[0] == "account"
    error_message = "Expected hub account PE to exist with subresource 'account'"
  }

  assert {
    condition     = azurerm_private_endpoint.research_account[0].private_service_connection[0].subresource_names[0] == "account"
    error_message = "Expected research account PE to exist with subresource 'account'"
  }
}

# ---------------------------------------------------------------------------
# 3. APIM virtual_network_type = "Internal" when flag is true
# ---------------------------------------------------------------------------
run "apim_vnet_type_internal_when_flag_true" {
  command = plan

  variables {
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    dns_zone_ids = {
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_api_management.main.virtual_network_type == "Internal"
    error_message = "APIM virtual_network_type must be Internal when flag is true"
  }
}

# ---------------------------------------------------------------------------
# 4. azapi_update_resource for APIM public access exists when flag is true
# ---------------------------------------------------------------------------
run "apim_update_resource_exists_when_flag_true" {
  command = plan

  variables {
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    dns_zone_ids = {
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azapi_update_resource.apim_disable_public_access[0].type == "Microsoft.ApiManagement/service@2023-05-01-preview"
    error_message = "Expected azapi_update_resource for APIM public access to exist with correct type"
  }

  assert {
    condition     = !can(azapi_update_resource.apim_disable_public_access[1].type)
    error_message = "Expected exactly one azapi_update_resource for APIM (not more)"
  }
}

# ---------------------------------------------------------------------------
# 5. APIM NSG exists when flag is true
# ---------------------------------------------------------------------------
run "apim_nsg_exists_when_flag_true" {
  command = plan

  variables {
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    dns_zone_ids = {
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_network_security_group.apim[0].location == var.location
    error_message = "Expected APIM NSG to exist in the correct location"
  }

  assert {
    condition     = !can(azurerm_network_security_group.apim[1].location)
    error_message = "Expected exactly one APIM NSG (not more)"
  }
}

# ---------------------------------------------------------------------------
# 6. time_sleep of 60s exists after hub account when flag is true
# ---------------------------------------------------------------------------
run "time_sleep_after_hub_account_when_flag_true" {
  command = plan

  variables {
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    dns_zone_ids = {
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = time_sleep.wait_hub_account[0].create_duration == "60s"
    error_message = "time_sleep after hub account must have create_duration = 60s"
  }

  assert {
    condition     = time_sleep.wait_research_account[0].create_duration == "60s"
    error_message = "time_sleep after research account must have create_duration = 60s"
  }
}
