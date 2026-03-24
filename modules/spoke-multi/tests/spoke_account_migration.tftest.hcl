# Tests for Phase 4: spoke-multi account migration + dependent resources + PEs.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared variables used across all tests (flag off by default).
variables {
  environment               = "dev"
  location                  = "swedencentral"
  enable_private_networking = false
  deployer_principal_id     = "00000000-0000-0000-0000-000000000001"
  teams                     = ["alpha"]
  apim_gateway_url          = "https://apim-test.azure-api.net"
  apim_subscription_keys    = { alpha = "test-key" }
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

# Reusable private_networking + dns_zone_ids values for flag=true tests.
# (Defined inline per run block — test files do not support top-level locals.)

# ---------------------------------------------------------------------------
# 1. Spoke account is an azapi_resource (not azurerm_cognitive_account)
# ---------------------------------------------------------------------------
run "spoke_account_is_azapi_resource" {
  command = plan

  assert {
    condition     = startswith(azapi_resource.spoke_account.type, "Microsoft.CognitiveServices/accounts@")
    error_message = "Expected spoke account to be an azapi_resource of type Microsoft.CognitiveServices/accounts@..."
  }
}

# ---------------------------------------------------------------------------
# 2. networkInjections absent when flag is false
# ---------------------------------------------------------------------------
run "network_injections_absent_when_flag_false" {
  command = plan

  variables {
    enable_private_networking = false
  }

  assert {
    condition     = !can(azapi_resource.spoke_account.body.properties.networkInjections)
    error_message = "Expected networkInjections to be absent in spoke account body when flag is false"
  }
}

# ---------------------------------------------------------------------------
# 3. networkInjections present with correct values when flag is true
# ---------------------------------------------------------------------------
run "network_injections_present_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azapi_resource.spoke_account.body.properties.networkInjections[0].scenario == "agent"
    error_message = "Expected networkInjections[0].scenario = 'agent' when flag is true"
  }

  assert {
    condition     = azapi_resource.spoke_account.body.properties.networkInjections[0].useMicrosoftManagedNetwork == false
    error_message = "Expected networkInjections[0].useMicrosoftManagedNetwork = false (BYO VNet)"
  }
}

# ---------------------------------------------------------------------------
# 4. Three dependent resources exist when flag is true
# ---------------------------------------------------------------------------
run "three_dependent_resources_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_storage_account.agent_storage[0].account_kind == "StorageV2"
    error_message = "Expected Storage account (StorageV2) to exist when flag is true"
  }

  assert {
    condition     = azurerm_cosmosdb_account.agent_cosmos[0].kind == "GlobalDocumentDB"
    error_message = "Expected CosmosDB account (GlobalDocumentDB) to exist when flag is true"
  }

  assert {
    condition     = startswith(azapi_resource.ai_search[0].type, "Microsoft.Search/searchServices@")
    error_message = "Expected AI Search (azapi_resource) to exist when flag is true"
  }
}

# ---------------------------------------------------------------------------
# 5. Zero dependent resources when flag is false
# ---------------------------------------------------------------------------
run "zero_dependent_resources_when_flag_false" {
  command = plan

  variables {
    enable_private_networking = false
  }

  assert {
    condition     = !can(azurerm_storage_account.agent_storage[0].account_kind)
    error_message = "Expected no Storage account when flag is false"
  }

  assert {
    condition     = !can(azurerm_cosmosdb_account.agent_cosmos[0].kind)
    error_message = "Expected no CosmosDB account when flag is false"
  }

  assert {
    condition     = !can(azapi_resource.ai_search[0].type)
    error_message = "Expected no AI Search when flag is false"
  }
}

# ---------------------------------------------------------------------------
# 6. Four private endpoints when flag is true
# ---------------------------------------------------------------------------
run "four_private_endpoints_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.spoke_account[0].private_service_connection[0].subresource_names[0] == "account"
    error_message = "Expected spoke account PE with subresource 'account'"
  }

  assert {
    condition     = azurerm_private_endpoint.storage[0].private_service_connection[0].subresource_names[0] == "blob"
    error_message = "Expected Storage PE with subresource 'blob'"
  }

  assert {
    condition     = azurerm_private_endpoint.cosmosdb[0].private_service_connection[0].subresource_names[0] == "Sql"
    error_message = "Expected CosmosDB PE with subresource 'Sql'"
  }

  assert {
    condition     = azurerm_private_endpoint.ai_search[0].private_service_connection[0].subresource_names[0] == "searchService"
    error_message = "Expected AI Search PE with subresource 'searchService'"
  }
}

# ---------------------------------------------------------------------------
# 7. CosmosDB local authentication disabled
# ---------------------------------------------------------------------------
run "cosmosdb_local_auth_disabled" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_cosmosdb_account.agent_cosmos[0].local_authentication_disabled == true
    error_message = "Expected local_authentication_disabled = true on CosmosDB (AAD-only auth)"
  }
}

# ---------------------------------------------------------------------------
# 8. Storage shared key disabled
# ---------------------------------------------------------------------------
run "storage_shared_key_disabled" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azurerm_storage_account.agent_storage[0].shared_access_key_enabled == false
    error_message = "Expected shared_access_key_enabled = false on Storage (AAD-only auth)"
  }
}
