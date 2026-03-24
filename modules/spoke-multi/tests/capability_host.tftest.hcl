# Tests for Phase 5: capability hosts, connections, and post-caphost RBAC.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# Shared variables: 3 teams, flag off by default.
variables {
  environment               = "dev"
  location                  = "swedencentral"
  enable_private_networking = false
  deployer_principal_id     = "00000000-0000-0000-0000-000000000001"
  teams                     = ["alpha", "beta", "gamma"]
  apim_gateway_url          = "https://apim-test.azure-api.net"
  apim_subscription_keys    = { alpha = "key-a", beta = "key-b", gamma = "key-c" }
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

# Reusable private_networking/dns_zone_ids values for flag=true tests.
# (Cannot use locals in test files — values are inlined per run block.)

# ---------------------------------------------------------------------------
# 1. Zero capability hosts when flag is false
# ---------------------------------------------------------------------------
run "zero_capability_hosts_when_flag_false" {
  command = plan

  variables {
    enable_private_networking = false
  }

  assert {
    condition     = length(azapi_resource.capability_host) == 0
    error_message = "Expected 0 capability hosts when flag is false"
  }
}

# ---------------------------------------------------------------------------
# 2. One capability host per team when flag is true
# ---------------------------------------------------------------------------
run "one_capability_host_per_team_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = length(azapi_resource.capability_host) == 3
    error_message = "Expected 3 capability hosts (one per team)"
  }
}

# ---------------------------------------------------------------------------
# 3. Three connections per project (9 total) when flag is true
# ---------------------------------------------------------------------------
run "three_connections_per_project_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = length(azapi_resource.cosmos_connection) == 3
    error_message = "Expected 3 CosmosDB connections (one per team)"
  }

  assert {
    condition     = length(azapi_resource.storage_connection) == 3
    error_message = "Expected 3 Storage connections (one per team)"
  }

  assert {
    condition     = length(azapi_resource.search_connection) == 3
    error_message = "Expected 3 AI Search connections (one per team)"
  }
}

# ---------------------------------------------------------------------------
# 4. All connections use AAD auth
# ---------------------------------------------------------------------------
run "all_connections_use_aad_auth" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azapi_resource.cosmos_connection["alpha"].body.properties.authType == "AAD"
    error_message = "Expected CosmosDB connection to use authType = AAD"
  }

  assert {
    condition     = azapi_resource.storage_connection["alpha"].body.properties.authType == "AAD"
    error_message = "Expected Storage connection to use authType = AAD"
  }

  assert {
    condition     = azapi_resource.search_connection["alpha"].body.properties.authType == "AAD"
    error_message = "Expected AI Search connection to use authType = AAD"
  }
}

# ---------------------------------------------------------------------------
# 5. Identity propagation sleep (10s) exists when flag is true
# ---------------------------------------------------------------------------
run "time_sleep_identity_exists_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = time_sleep.wait_project_identities["alpha"].create_duration == "10s"
    error_message = "Expected 10s identity propagation sleep for team alpha"
  }

  assert {
    condition     = length(time_sleep.wait_project_identities) == 3
    error_message = "Expected one identity sleep per team (3 total)"
  }
}

# ---------------------------------------------------------------------------
# 6. RBAC propagation sleep (60s) exists when flag is true
# ---------------------------------------------------------------------------
run "time_sleep_rbac_exists_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = time_sleep.wait_rbac["alpha"].create_duration == "60s"
    error_message = "Expected 60s RBAC propagation sleep for team alpha"
  }

  assert {
    condition     = length(time_sleep.wait_rbac) == 3
    error_message = "Expected one RBAC sleep per team (3 total)"
  }
}

# ---------------------------------------------------------------------------
# 7. Capability host type contains the preview API version
# ---------------------------------------------------------------------------
run "caphost_api_is_preview" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = azapi_resource.capability_host["alpha"].type == "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
    error_message = "Expected capability host type to include 2025-04-01-preview API version"
  }
}

# ---------------------------------------------------------------------------
# 8. Four RBAC assignments per project (12 total) when flag is true
# ---------------------------------------------------------------------------
run "four_rbac_assignments_per_project_when_flag_true" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.cosmos_operator) == 3
    error_message = "Expected 3 CosmosDB Operator role assignments (one per team)"
  }

  assert {
    condition     = length(azurerm_role_assignment.storage_blob_contributor) == 3
    error_message = "Expected 3 Storage Blob Data Contributor role assignments (one per team)"
  }

  assert {
    condition     = length(azurerm_role_assignment.search_index_contributor) == 3
    error_message = "Expected 3 Search Index Data Contributor role assignments (one per team)"
  }

  assert {
    condition     = length(azurerm_role_assignment.search_service_contributor) == 3
    error_message = "Expected 3 Search Service Contributor role assignments (one per team)"
  }
}

# ---------------------------------------------------------------------------
# 9. Post-caphost CosmosDB SQL role assignments: 3 per project = 9 total
# ---------------------------------------------------------------------------
run "post_caphost_cosmos_sql_roles_per_project" {
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
      cognitive_services = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services_ai        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
      search             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
      documents          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
      blob               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      file               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
      apim               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
    }
  }

  assert {
    condition     = length(azurerm_cosmosdb_sql_role_assignment.postcaphost_cosmos) == 9
    error_message = "Expected 9 CosmosDB SQL role assignments (3 collections × 3 teams)"
  }
}
