# =============================================================================
# RESOURCE GROUP
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = local.spoke_rg_name
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# SHARED FOUNDRY ACCOUNT (aif-spoke-multi)
# Migrated to azapi_resource to support networkInjections for private networking.
# No local model deployments — all inference routes via APIM to the hub.
# =============================================================================

resource "azapi_resource" "spoke_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.spoke_account_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = merge(
      {
        allowProjectManagement = true
        customSubDomainName    = local.spoke_subdomain
        publicNetworkAccess    = var.enable_private_networking ? "Disabled" : "Enabled"
        # Private endpoint connections bypass networkAcls entirely, so "Deny" here
        # does not block private endpoint traffic. "Allow" allows public internet
        # traffic even when publicNetworkAccess = "Disabled" — use "Deny" to enforce
        # isolation when private networking is enabled.
        networkAcls = {
          defaultAction = var.enable_private_networking ? "Deny" : "Allow"
        }
      },
      var.enable_private_networking ? {
        networkInjections = [{
          scenario                   = "agent"
          subnetArmId                = var.private_networking.spoke_agent_subnet_id
          useMicrosoftManagedNetwork = false
        }]
      } : {}
    )
  }

  response_export_values = ["properties.endpoint"]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Race-condition sleep: ARM provisioning state can take ~60s to stabilise.
# Only needed when private endpoints are being created (flag = true).
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_spoke_account" {
  count = var.enable_private_networking ? 1 : 0

  create_duration = "60s"
  depends_on      = [azapi_resource.spoke_account]
}

# ---------------------------------------------------------------------------
# Private endpoint: spoke AI Services account
# Subresource "account" — DNS covers cognitiveservices, openai, services.ai.
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "spoke_account" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.spoke_account_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.spoke_account_name}-psc"
    private_connection_resource_id = azapi_resource.spoke_account.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "spoke-account-dns"
    private_dns_zone_ids = [
      var.dns_zone_ids.cognitive_services,
      var.dns_zone_ids.openai,
      var.dns_zone_ids.services_ai,
    ]
  }

  depends_on = [time_sleep.wait_spoke_account]

  tags = local.common_tags
}

# =============================================================================
# AGENT STORAGE ACCOUNT (conditional: enable_private_networking = true)
# =============================================================================

resource "azapi_resource" "agent_storage" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = local.agent_storage_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  schema_validation_enabled = false

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_ZRS" }
    properties = {
      allowSharedKeyAccess    = false
      publicNetworkAccess     = "Disabled"
      allowBlobPublicAccess   = false
      minimumTlsVersion       = "TLS1_2"
      # networkAcls.resourceAccessRules — trusted-service bypass for the spoke
      # account and every per-team project. Needed in addition to the private
      # endpoint: the agent runtime's data-plane reads can come via the PE from
      # snet-agents-spoke, but Foundry's control-plane services (Files API,
      # agent orchestrator) run in Microsoft-managed network and reach this
      # storage account from MS-owned IPs. With publicNetworkAccess = "Disabled"
      # those calls would be rejected unless the calling resource's ARM ID is
      # explicitly trusted here. See 99-docs/storage-trusted-bypass-rationale.md.
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
        resourceAccessRules = concat(
          [{
            resourceId = azapi_resource.spoke_account.id
            tenantId   = data.azurerm_client_config.current.tenant_id
          }],
          [for k in var.teams : {
            resourceId = azapi_resource.team_project[k].id
            tenantId   = data.azurerm_client_config.current.tenant_id
          }],
        )
      }
    }
  }

  response_export_values = ["properties.primaryEndpoints.blob"]

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "storage" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.agent_storage_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.agent_storage_name}-psc"
    private_connection_resource_id = azapi_resource.agent_storage[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name             = "storage-dns"
    private_dns_zone_ids = [var.dns_zone_ids.blob]
  }

  depends_on = [azapi_resource.agent_storage, azurerm_private_endpoint.spoke_account]

  tags = local.common_tags
}

# =============================================================================
# AGENT COSMOSDB ACCOUNT (conditional: enable_private_networking = true)
# =============================================================================

resource "azurerm_cosmosdb_account" "agent_cosmos" {
  count = var.enable_private_networking ? 1 : 0

  name                = local.agent_cosmos_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  local_authentication_disabled = true
  public_network_access_enabled = false
  automatic_failover_enabled    = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = false
  }

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "cosmosdb" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.agent_cosmos_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.agent_cosmos_name}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.agent_cosmos[0].id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name             = "cosmosdb-dns"
    private_dns_zone_ids = [var.dns_zone_ids.documents]
  }

  depends_on = [azurerm_cosmosdb_account.agent_cosmos, azurerm_private_endpoint.storage]

  tags = local.common_tags
}

# =============================================================================
# AGENT AI SEARCH SERVICE (conditional: enable_private_networking = true)
# Uses azapi_resource — azurerm_search_service lacks the required API version.
# =============================================================================

resource "azapi_resource" "ai_search" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = local.agent_search_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  schema_validation_enabled = false

  body = {
    sku = { name = "standard" }
    properties = {
      publicNetworkAccess = "Disabled"
      disableLocalAuth    = false
      networkRuleSet      = { bypass = "None" }
    }
  }

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "ai_search" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.agent_search_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.agent_search_name}-psc"
    private_connection_resource_id = azapi_resource.ai_search[0].id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name             = "search-dns"
    private_dns_zone_ids = [var.dns_zone_ids.search]
  }

  depends_on = [azapi_resource.ai_search, azurerm_private_endpoint.cosmosdb]

  tags = local.common_tags
}

# =============================================================================
# TEAM PROJECTS — one per team via azapi_resource (migrated from azurerm_cognitive_account_project
# to allow exporting properties.internalId for CosmosDB collection scoping).
# =============================================================================

resource "azapi_resource" "team_project" {
  for_each = toset(var.teams)

  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "project-${each.key}-${local.subscription_suffix}"
  parent_id = azapi_resource.spoke_account.id
  location  = azapi_resource.spoke_account.location

  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = "Project for team ${each.key} connecting to core gateway via APIM"
    }
  }

  # internalId is used to build CosmosDB collection scope paths.
  # identity is read back for managed-identity RBAC assignments.
  response_export_values = ["properties.internalId"]

  tags = local.common_tags
}

# =============================================================================
# APIM CONNECTIONS — one per team via azapi_resource
#
# azurerm has no support for project connections yet:
# https://github.com/hashicorp/terraform-provider-azurerm/issues/29188
#
# metadata.models MUST be jsonencode()'d — a raw HCL object creates the
# resource but Foundry won't surface models in the project UI.
#
# All string values are case-sensitive: "ApiManagement", "ApiKey".
# target must use the .azure-api.net FQDN, not a custom domain.
# =============================================================================

resource "azapi_resource" "core_connection" {
  for_each = toset(var.teams)

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "core-${each.key}"
  parent_id = azapi_resource.team_project[each.key].id

  body = {
    properties = {
      category = "ApiManagement"
      target   = "${var.apim_gateway_url}/openai"
      authType = "ApiKey"
      credentials = {
        key = var.apim_subscription_keys[each.key]
      }
      metadata = {
        deploymentInPath    = "true"
        inferenceAPIVersion = "2024-10-21"
        models              = jsonencode(local.all_models)
      }
    }
  }
}

# =============================================================================
# PHASE 5: CAPABILITY HOSTS, CONNECTIONS, AND POST-CAPHOST RBAC
# All resources conditional on enable_private_networking.
# =============================================================================

# ---------------------------------------------------------------------------
# Step 1: Wait for project managed identities to propagate in AAD (10s).
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_project_identities" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  create_duration = "10s"
  depends_on      = [azapi_resource.team_project]
}

# ---------------------------------------------------------------------------
# Step 2: Pre-caphost RBAC — project MI needs access to dependent resources
# before the capability host can be created.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "cosmos_operator" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  scope              = azurerm_cosmosdb_account.agent_cosmos[0].id
  role_definition_name = "Cosmos DB Operator"
  principal_id       = azapi_resource.team_project[each.key].identity[0].principal_id

  depends_on = [time_sleep.wait_project_identities]
}

resource "azurerm_role_assignment" "storage_blob_contributor" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  scope              = azapi_resource.agent_storage[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id       = azapi_resource.team_project[each.key].identity[0].principal_id

  depends_on = [time_sleep.wait_project_identities]
}

# Spoke Foundry account MSI also needs data-plane access on agent_storage.
# The agent service uses this identity for control-plane operations across
# every team project hosted on this account. Single assignment — the storage
# account is shared across all team projects on this spoke. Network-allow
# alone is insufficient — RBAC is evaluated after networkAcls passes.
# See 99-docs/storage-trusted-bypass-rationale.md.
resource "azurerm_role_assignment" "spoke_account_storage_blob_contributor" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.agent_storage[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.spoke_account.identity[0].principal_id

  depends_on = [time_sleep.wait_spoke_account[0]]
}

# ---------------------------------------------------------------------------
# Operator RBAC — per-team 'Azure AI Project Manager' assignments.
# Required for portal users to invoke agents in each team's Build pane /
# playground. Subscription-level 'Azure AI User' does NOT satisfy nextgen
# Foundry's project-scoped data-plane auth; without these entries, those
# users see HTTP 403 on Agents_Wildcard_Get and the agent UI returns a
# generic error. See 99-docs/core-account-admin-project-setup.md §12.
# ---------------------------------------------------------------------------

locals {
  team_admin_assignments = flatten([
    for team, principals in var.team_admin_principals : [
      for p in principals : {
        team           = team
        object_id      = p.object_id
        principal_type = p.principal_type
        key            = "${team}-${p.object_id}"
      }
    ]
  ])
}

resource "azurerm_role_assignment" "team_project_manager" {
  for_each = {
    for a in local.team_admin_assignments : a.key => a
  }

  scope                = azapi_resource.team_project[each.value.team].id
  role_definition_name = "Azure AI Project Manager"
  principal_id         = each.value.object_id
  principal_type       = each.value.principal_type
}

resource "azurerm_role_assignment" "search_index_contributor" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  scope              = azapi_resource.ai_search[0].id
  role_definition_name = "Search Index Data Contributor"
  principal_id       = azapi_resource.team_project[each.key].identity[0].principal_id

  depends_on = [time_sleep.wait_project_identities]
}

resource "azurerm_role_assignment" "search_service_contributor" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  scope              = azapi_resource.ai_search[0].id
  role_definition_name = "Search Service Contributor"
  principal_id       = azapi_resource.team_project[each.key].identity[0].principal_id

  depends_on = [time_sleep.wait_project_identities]
}

# ---------------------------------------------------------------------------
# Step 3: Wait for RBAC to propagate before creating connections/caphost (60s).
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_rbac" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.cosmos_operator,
    azurerm_role_assignment.storage_blob_contributor,
    azurerm_role_assignment.spoke_account_storage_blob_contributor,
    azurerm_role_assignment.search_index_contributor,
    azurerm_role_assignment.search_service_contributor,
  ]
}

# ---------------------------------------------------------------------------
# Step 4: Project connections (CosmosDB, Storage, AI Search) — AAD auth.
# Connections reference the underlying service name (not full resource ID).
# ---------------------------------------------------------------------------

resource "azapi_resource" "cosmos_connection" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "cosmos-${each.key}"
  parent_id = azapi_resource.team_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.agent_cosmos[0].endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.agent_cosmos[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_rbac]
}

resource "azapi_resource" "storage_connection" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "storage-${each.key}"
  parent_id = azapi_resource.team_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = azapi_resource.agent_storage[0].output.properties.primaryEndpoints.blob
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.agent_storage[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_rbac]
}

resource "azapi_resource" "search_connection" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "search-${each.key}"
  parent_id = azapi_resource.team_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azapi_resource.ai_search[0].name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2025-05-01-preview"
        ResourceId = azapi_resource.ai_search[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_rbac]
}

# ---------------------------------------------------------------------------
# Step 5: Capability host — one per project.
# References connections by name (not resource ID).
# ---------------------------------------------------------------------------

resource "azapi_resource" "capability_host" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphostproj-${each.key}"
  parent_id = azapi_resource.team_project[each.key].id

  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = ["search-${each.key}"]
      storageConnections       = ["storage-${each.key}"]
      threadStorageConnections = ["cosmos-${each.key}"]
    }
  }

  depends_on = [
    azapi_resource.cosmos_connection,
    azapi_resource.storage_connection,
    azapi_resource.search_connection,
  ]
}

# ---------------------------------------------------------------------------
# Step 6: Post-caphost CosmosDB SQL roles — scoped to the enterprise_memory database.
#
# Scope is set at the database level rather than individual collections because
# the agent service creates collections lazily at runtime (e.g. agent-definitions-v1
# is created on first agent list/create). Collection-scoped role assignments fail
# at apply time if the collection does not yet exist, and would silently break
# new collection types added by Azure in future SDK versions.
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "postcaphost_cosmos" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.agent_cosmos[0].name
  role_definition_id  = "${azurerm_cosmosdb_account.agent_cosmos[0].id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.team_project[each.key].identity[0].principal_id
  scope               = "${azurerm_cosmosdb_account.agent_cosmos[0].id}/dbs/enterprise_memory"

  depends_on = [azapi_resource.capability_host]
}

# ---------------------------------------------------------------------------
# Step 7: Post-caphost Storage ABAC — scopes writes/reads to the project's
# container prefix (project_id_guid*-azureml-agent).
# NOTE: condition is (known after apply) due to project_id_guid dependency.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "storage_blob_data_owner" {
  for_each = var.enable_private_networking ? toset(var.teams) : toset([])

  scope              = azapi_resource.agent_storage[0].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id       = azapi_resource.team_project[each.key].identity[0].principal_id

  condition_version = "2.0"
  condition         = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'})
        AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'})
        AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})
        AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'})
      )
      OR
      (
        @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWith '${local.project_id_guid[each.key]}'
      )
    )
  EOT

  depends_on = [azapi_resource.capability_host]
}

# =============================================================================
# RBAC — deployer gets Cognitive Services User on the shared account
# =============================================================================

resource "azurerm_role_assignment" "deployer" {
  scope              = azapi_resource.spoke_account.id
  role_definition_name = "Cognitive Services User"
  principal_id       = var.deployer_principal_id
}
