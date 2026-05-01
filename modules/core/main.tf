# =============================================================================
# RESOURCE GROUP
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = local.core_rg_name
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# CORE FOUNDRY ACCOUNT (aif-core) — primary core: general-purpose models
# Uses azapi_resource to support networkInjections for private networking.
# =============================================================================

resource "azapi_resource" "core_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.core_account_name
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
        customSubDomainName    = local.core_subdomain
        localAuthEnabled       = false
        publicNetworkAccess    = var.enable_private_networking ? "Disabled" : "Enabled"
        networkAcls = {
          defaultAction = var.enable_private_networking ? "Deny" : "Allow"
        }
      },
      var.enable_private_networking ? {
        networkInjections = [{
          scenario                   = "agent"
          subnetArmId                = var.private_networking.agent_subnet_id
          useMicrosoftManagedNetwork = false
        }]
      } : {}
    )
  }

  response_export_values = ["properties.endpoint"]

  tags = local.common_tags
}

# Core model deployments.
#
# Serialization: concurrent deployments on the same account can produce HTTP
# 409 conflicts. We serialize by chaining depends_on through an ordered list
# derived from the core_models variable. The caller controls order via tfvars.
#
# version_upgrade_option = "NoAutoUpgrade" — required to prevent Azure from
# silently upgrading model versions between Terraform runs (which would cause
# behavioral drift without any plan showing changes).

locals {
  core_models_ordered = [for m in var.core_models : m]
}

resource "azurerm_cognitive_deployment" "core" {
  for_each = { for m in var.core_models : m.name => m }

  name                 = each.key
  cognitive_account_id = azapi_resource.core_account.id

  model {
    format  = each.value.format
    name    = each.value.name
    version = each.value.version
  }

  sku {
    name     = each.value.sku
    capacity = each.value.capacity
  }

  version_upgrade_option = "NoAutoUpgrade"

  # Serialize deployments on this account to avoid HTTP 409 conflicts.
  # Each deployment depends on all others that precede it in the ordered list.
  depends_on = [azapi_resource.core_account]
}

# =============================================================================
# RESEARCH FOUNDRY ACCOUNT (aif-research) — var.research_location (default: norwayeast), reasoning models
# =============================================================================

resource "azurerm_cognitive_account" "research" {
  name                       = local.research_account_name
  location                   = var.research_location
  resource_group_name        = azurerm_resource_group.main.name
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = local.research_subdomain
  project_management_enabled = true
  local_auth_enabled         = false

  public_network_access_enabled = !var.enable_private_networking

  dynamic "network_acls" {
    for_each = var.enable_private_networking ? [1] : []
    content {
      default_action = "Deny"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

resource "azurerm_cognitive_deployment" "research" {
  for_each = { for m in var.research_models : m.name => m }

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.research.id

  model {
    format  = each.value.format
    name    = each.value.name
    version = each.value.version
  }

  sku {
    name     = each.value.sku
    capacity = each.value.capacity
  }

  version_upgrade_option = "NoAutoUpgrade"

  depends_on = [azurerm_cognitive_account.research]
}

# =============================================================================
# APIM SERVICE
# Note: StandardV2 provisioning takes 15–20 minutes on first apply.
# =============================================================================

resource "azurerm_api_management" "main" {
  name                = local.apim_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "StandardV2_1"

  # StandardV2 supports outbound VNet integration via "External" virtual_network_type
  # (this is distinct from Premium "Internal" VNet injection — StandardV2 External mode
  # routes APIM outbound traffic through snet-apim so it can reach private backends).
  # When private networking is disabled, no VNet integration is needed.
  # public_network_access_enabled is managed post-creation via azapi_update_resource
  # (Azure rejects disabling it at creation time); ignore drift here.
  virtual_network_type = var.enable_private_networking ? "External" : "None"

  dynamic "virtual_network_configuration" {
    for_each = var.enable_private_networking ? [1] : []
    content {
      subnet_id = var.private_networking.apim_subnet_id
    }
  }

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# =============================================================================
# APIM BACKENDS
# =============================================================================

resource "azurerm_api_management_backend" "hub" {
  name                = "openai"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "${azapi_resource.core_account.output.properties.endpoint}openai"
}

resource "azurerm_api_management_backend" "research" {
  name                = "openai-research"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "${azurerm_cognitive_account.research.endpoint}openai"
  description         = "Research hub — reasoning models"
}

# =============================================================================
# APIM API
# =============================================================================

resource "azurerm_api_management_api" "main" {
  name                = "openai"
  display_name        = "OpenAI"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  path                = "openai"
  protocols           = ["https"]
  subscription_required = true

  subscription_key_parameter_names {
    header = "api-key"
    query  = "api-key"
  }
}

# =============================================================================
# APIM OPERATIONS (4 total — chat-oss excluded per scope)
# =============================================================================

resource "azurerm_api_management_api_operation" "chat" {
  operation_id        = "chat"
  display_name        = "Chat Completions"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  method              = "POST"
  url_template        = "/deployments/{deployment-id}/chat/completions"

  template_parameter {
    name     = "deployment-id"
    required = true
    type     = "string"
  }
}

resource "azurerm_api_management_api_operation" "chat_research" {
  operation_id        = "chat-research"
  display_name        = "Chat Completions (Research)"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  method              = "POST"
  url_template        = "/deployments/o3-deep-research/chat/completions"
}

resource "azurerm_api_management_api_operation" "embeddings" {
  operation_id        = "embeddings"
  display_name        = "Embeddings"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  method              = "POST"
  url_template        = "/deployments/{deployment-id}/embeddings"

  template_parameter {
    name     = "deployment-id"
    required = true
    type     = "string"
  }
}

resource "azurerm_api_management_api_operation" "responses" {
  operation_id        = "responses"
  display_name        = "Responses"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  method              = "POST"
  url_template        = "/responses"
}

# =============================================================================
# APIM OPERATION POLICIES
# =============================================================================

# Operation-level policy for chat-research — overrides backend to openai-research.
resource "azurerm_api_management_api_operation_policy" "chat_research" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  operation_id        = azurerm_api_management_api_operation.chat_research.operation_id

  xml_content = templatefile("${path.module}/templates/chat_research_policy.xml.tftpl", {
    backend_id = "openai-research"
  })
}

# =============================================================================
# APIM API-LEVEL POLICY (All Operations)
# =============================================================================

resource "azurerm_api_management_api_policy" "main" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = templatefile("${path.module}/templates/api_policy.xml.tftpl", {
    backend_id        = "openai"
    rate_limit_calls  = 100
    rate_limit_period = 60
  })
}

# =============================================================================
# APIM SUBSCRIPTIONS — one per team
# =============================================================================

resource "azurerm_api_management_subscription" "team" {
  for_each = toset(var.teams)

  display_name        = "Foundry Gateway Access (${title(each.key)})"
  subscription_id     = "foundry-gateway-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  api_id              = replace(azurerm_api_management_api.main.id, ";rev=${azurerm_api_management_api.main.revision}", "")
  state               = "active"
}

# =============================================================================
# RBAC ROLE ASSIGNMENTS — Cognitive Services User (a97b65f3-...)
# =============================================================================

resource "azurerm_role_assignment" "apim_core" {
  scope                = azapi_resource.core_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "apim_research" {
  scope                = azurerm_cognitive_account.research.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "deployer_core" {
  scope                = azapi_resource.core_account.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.deployer_principal_id
}

resource "azurerm_role_assignment" "deployer_research" {
  scope                = azurerm_cognitive_account.research.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.deployer_principal_id
}

# Operator RBAC at the admin project scope — required for portal users to
# invoke agents. Subscription-level 'Azure AI User' does NOT satisfy
# nextgen Foundry's project-scoped data-plane auth; without these entries,
# the Agents_Wildcard_Get API returns 403 to the user's portal session.
# See 99-docs/core-account-admin-project-setup.md §12.
resource "azurerm_role_assignment" "admin_project_manager" {
  for_each = var.enable_private_networking ? {
    for p in var.project_admin_principals : p.object_id => p
  } : {}

  scope                = azapi_resource.admin_project[0].id
  role_definition_name = "Azure AI Project Manager"
  principal_id         = each.value.object_id
  principal_type       = each.value.principal_type
}

# =============================================================================
# PRIVATE NETWORKING — conditional on var.enable_private_networking
# =============================================================================

# ---------------------------------------------------------------------------
# Race condition sleeps — avoids AccountProvisioningStateInvalid on PE creation
# (azurerm #31712)
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_core_account" {
  count          = var.enable_private_networking ? 1 : 0
  create_duration = "60s"
  depends_on     = [azapi_resource.core_account]
}

resource "time_sleep" "wait_research_account" {
  count          = var.enable_private_networking ? 1 : 0
  create_duration = "120s"
  depends_on     = [azurerm_cognitive_account.research]
}

# ---------------------------------------------------------------------------
# Private endpoints — AI accounts
# Sequential chain (each depends on previous) prevents ARM parallelism races.
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "core_account" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-${local.core_account_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.core_account_name}"
    private_connection_resource_id = azapi_resource.core_account.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "core-account-dns"
    private_dns_zone_ids = [
      var.dns_zone_ids.cognitive_services,
      var.dns_zone_ids.openai,
      var.dns_zone_ids.services_ai,
    ]
  }

  depends_on = [time_sleep.wait_core_account[0]]
}

resource "azurerm_private_endpoint" "research_account" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-${local.research_account_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.research_account_name}"
    private_connection_resource_id = azurerm_cognitive_account.research.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "research-account-dns"
    private_dns_zone_ids = [
      var.dns_zone_ids.cognitive_services,
      var.dns_zone_ids.openai,
      var.dns_zone_ids.services_ai,
    ]
  }

  depends_on = [time_sleep.wait_research_account, azurerm_private_endpoint.core_account]
}

# ---------------------------------------------------------------------------
# APIM NSG — required before APIM resource creation in Internal VNet mode.
# Ruleset per Microsoft docs:
# https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "apim" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "nsg-${local.apim_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # --- Inbound rules ---

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAPIMManagement"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  # --- Outbound rules ---

  security_rule {
    name                       = "AllowStorageOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowSqlOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "AllowKeyVaultOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowSqlMonitorOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "12000"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  count                     = var.enable_private_networking ? 1 : 0
  subnet_id                 = var.private_networking.apim_subnet_id
  network_security_group_id = azurerm_network_security_group.apim[0].id
}

# ---------------------------------------------------------------------------
# APIM private endpoint
# Must be created BEFORE disabling public access — Azure rejects the PATCH
# unless at least one approved private endpoint connection already exists.
# Sequential: depends on the research_account PE to avoid ARM parallelism races.
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "apim" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-${local.apim_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.apim_name}"
    private_connection_resource_id = azurerm_api_management.main.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "apim-dns"
    private_dns_zone_ids = [
      var.dns_zone_ids.apim,
    ]
  }

  depends_on = [azurerm_private_endpoint.research_account]
}

# ---------------------------------------------------------------------------
# APIM — disable public access post-creation via PATCH.
# Must run AFTER the private endpoint is approved, otherwise Azure returns
# DisablingPublicNetworkAccessRequiredPrivateEndpoint (400).
# ---------------------------------------------------------------------------

resource "azapi_update_resource" "apim_disable_public_access" {
  count       = var.enable_private_networking ? 1 : 0
  type        = "Microsoft.ApiManagement/service@2023-05-01-preview"
  resource_id = azurerm_api_management.main.id

  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }

  depends_on = [azurerm_private_endpoint.apim]
}

# =============================================================================
# ADMIN CAPABILITY HOST BACKING RESOURCES
# All resources conditional on enable_private_networking = true.
# Mirrors the same pattern used in the spoke-multi module.
# =============================================================================

# ---------------------------------------------------------------------------
# Storage account
# ---------------------------------------------------------------------------

resource "azapi_resource" "core_storage" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = local.core_storage_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  schema_validation_enabled = false

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_ZRS" }
    properties = {
      allowSharedKeyAccess  = false
      publicNetworkAccess   = "Disabled"
      allowBlobPublicAccess = false
      minimumTlsVersion     = "TLS1_2"
      # networkAcls.resourceAccessRules — trusted-service bypass for the Foundry
      # account and admin project. Needed in addition to the private endpoint:
      # the agent runtime's data-plane reads can come via the PE from snet-agents,
      # but Foundry's control-plane services (Files API, agent orchestrator)
      # run in Microsoft-managed network and reach the storage account from
      # MS-owned IPs. With publicNetworkAccess = "Disabled" those calls would be
      # rejected unless the calling resource's ARM ID is explicitly trusted here.
      # See 99-docs/storage-trusted-bypass-rationale.md.
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
        resourceAccessRules = [
          {
            resourceId = azapi_resource.core_account.id
            tenantId   = data.azurerm_client_config.current.tenant_id
          },
          {
            resourceId = azapi_resource.admin_project[0].id
            tenantId   = data.azurerm_client_config.current.tenant_id
          },
        ]
      }
    }
  }

  response_export_values = ["properties.primaryEndpoints.blob"]

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "core_storage" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.core_storage_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.core_storage_name}-psc"
    private_connection_resource_id = azapi_resource.core_storage[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "storage-dns"
    private_dns_zone_ids = [var.dns_zone_ids.blob]
  }

  depends_on = [azapi_resource.core_storage, azurerm_private_endpoint.core_account]
}

# ---------------------------------------------------------------------------
# CosmosDB account
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_account" "core_cosmos" {
  count = var.enable_private_networking ? 1 : 0

  name                = local.core_cosmos_name
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

resource "azurerm_private_endpoint" "core_cosmos" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.core_cosmos_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.core_cosmos_name}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.core_cosmos[0].id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmosdb-dns"
    private_dns_zone_ids = [var.dns_zone_ids.documents]
  }

  depends_on = [azurerm_cosmosdb_account.core_cosmos, azurerm_private_endpoint.core_storage]
}

# ---------------------------------------------------------------------------
# AI Search service
# ---------------------------------------------------------------------------

resource "azapi_resource" "core_search" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = local.core_search_name
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

resource "azurerm_private_endpoint" "core_search" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-${local.core_search_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_networking.private_endpoint_subnet_id
  tags                = local.common_tags

  private_service_connection {
    name                           = "${local.core_search_name}-psc"
    private_connection_resource_id = azapi_resource.core_search[0].id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "search-dns"
    private_dns_zone_ids = [var.dns_zone_ids.search]
  }

  depends_on = [azapi_resource.core_search, azurerm_private_endpoint.core_cosmos]
}

# =============================================================================
# ADMIN PROJECT
# =============================================================================

resource "azapi_resource" "admin_project" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "project-admin-${local.subscription_suffix}"
  parent_id = azapi_resource.core_account.id
  location  = azapi_resource.core_account.location

  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = "Admin project for model evaluation and playground access"
    }
  }

  response_export_values = ["properties.internalId"]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Wait for admin project managed identity to propagate in AAD (10s).
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_admin_project_identity" {
  count = var.enable_private_networking ? 1 : 0

  create_duration = "10s"
  depends_on      = [azapi_resource.admin_project]
}

# ---------------------------------------------------------------------------
# Pre-caphost RBAC — project MI needs access to backing resources.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "admin_cosmos_operator" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azurerm_cosmosdb_account.core_cosmos[0].id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.admin_project[0].identity[0].principal_id

  depends_on = [time_sleep.wait_admin_project_identity]
}

resource "azurerm_role_assignment" "admin_storage_blob_contributor" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.core_storage[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.admin_project[0].identity[0].principal_id

  depends_on = [time_sleep.wait_admin_project_identity]
}

# Foundry account MSI also needs data-plane access on core_storage.
# The agent service uses this identity for control-plane operations
# (Files API uploads, blob lifecycle on user-attached files, intermediate
# artifacts). Network-allow alone is insufficient — RBAC is evaluated
# after networkAcls passes. See 99-docs/storage-trusted-bypass-rationale.md.
resource "azurerm_role_assignment" "core_account_storage_blob_contributor" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.core_storage[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.core_account.identity[0].principal_id

  depends_on = [time_sleep.wait_core_account[0]]
}

resource "azurerm_role_assignment" "admin_search_index_contributor" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.core_search[0].id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.admin_project[0].identity[0].principal_id

  depends_on = [time_sleep.wait_admin_project_identity]
}

resource "azurerm_role_assignment" "admin_search_service_contributor" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.core_search[0].id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.admin_project[0].identity[0].principal_id

  depends_on = [time_sleep.wait_admin_project_identity]
}

# ---------------------------------------------------------------------------
# Wait for RBAC to propagate before creating connections/caphost (60s).
# ---------------------------------------------------------------------------

resource "time_sleep" "wait_admin_rbac" {
  count = var.enable_private_networking ? 1 : 0

  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.admin_cosmos_operator,
    azurerm_role_assignment.admin_storage_blob_contributor,
    azurerm_role_assignment.core_account_storage_blob_contributor,
    azurerm_role_assignment.admin_search_index_contributor,
    azurerm_role_assignment.admin_search_service_contributor,
  ]
}

# ---------------------------------------------------------------------------
# Project connections (CosmosDB, Storage, AI Search) — AAD auth.
# ---------------------------------------------------------------------------

resource "azapi_resource" "admin_cosmos_connection" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "cosmos-admin"
  parent_id = azapi_resource.admin_project[0].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.core_cosmos[0].endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.core_cosmos[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_admin_rbac]
}

resource "azapi_resource" "admin_storage_connection" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "storage-admin"
  parent_id = azapi_resource.admin_project[0].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = azapi_resource.core_storage[0].output.properties.primaryEndpoints.blob
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.core_storage[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_admin_rbac]
}

resource "azapi_resource" "admin_search_connection" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "search-admin"
  parent_id = azapi_resource.admin_project[0].id

  schema_validation_enabled = false

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azapi_resource.core_search[0].name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2025-05-01-preview"
        ResourceId = azapi_resource.core_search[0].id
        location   = azurerm_resource_group.main.location
      }
    }
  }

  depends_on = [time_sleep.wait_admin_rbac]
}

# ---------------------------------------------------------------------------
# Capability host — unlocks Agent Service and playground for the admin project.
# ---------------------------------------------------------------------------

resource "azapi_resource" "admin_capability_host" {
  count = var.enable_private_networking ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphost-admin"
  parent_id = azapi_resource.admin_project[0].id

  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = ["search-admin"]
      storageConnections       = ["storage-admin"]
      threadStorageConnections = ["cosmos-admin"]
    }
  }

  depends_on = [
    azapi_resource.admin_cosmos_connection,
    azapi_resource.admin_storage_connection,
    azapi_resource.admin_search_connection,
  ]
}

# ---------------------------------------------------------------------------
# Post-caphost CosmosDB SQL roles — scoped to the enterprise_memory database.
#
# Scope is set at the database level rather than individual collections because
# the agent service creates collections lazily at runtime (e.g. agent-definitions-v1
# is created on first agent list/create). Collection-scoped role assignments fail
# at apply time if the collection does not yet exist, and would silently break
# new collection types added by Azure in future SDK versions.
# ---------------------------------------------------------------------------

resource "azurerm_cosmosdb_sql_role_assignment" "admin_postcaphost_cosmos" {
  count = var.enable_private_networking ? 1 : 0

  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.core_cosmos[0].name
  role_definition_id  = "${azurerm_cosmosdb_account.core_cosmos[0].id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.admin_project[0].identity[0].principal_id
  scope               = "${azurerm_cosmosdb_account.core_cosmos[0].id}/dbs/enterprise_memory"

  depends_on = [azapi_resource.admin_capability_host]
}

# ---------------------------------------------------------------------------
# Post-caphost Storage ABAC — scopes access to the admin project's container.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "admin_storage_blob_data_owner" {
  count = var.enable_private_networking ? 1 : 0

  scope                = azapi_resource.core_storage[0].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.admin_project[0].identity[0].principal_id

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
        @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWith '${local.admin_project_id_guid}'
      )
    )
  EOT

  depends_on = [azapi_resource.admin_capability_host]
}
