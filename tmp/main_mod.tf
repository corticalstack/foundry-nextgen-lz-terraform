# main_mod.tf — capability-host-enabled version of main.tf
#
# Changes from main.tf:
#   1. Added data sources: PE subnet + blob/documents DNS zones (needed for inline PEs below)
#   2. Added: module "caphost_search" — dedicated AI Search for capability host
#             (separate from module "ai_search_direct" which serves direct/shared access)
#   3. Added: azapi_resource.caphost_storage — dedicated Storage Account for capability host
#   4. Added: azurerm_private_endpoint.caphost_storage_blob — PE for blob sub-resource
#   5. Added: azurerm_cosmosdb_account.caphost_cosmos — dedicated CosmosDB for capability host
#             (separate from module "cosmos" which is scoped to usage/billing tracking)
#   6. Added: azurerm_cosmosdb_sql_database.caphost_enterprise_memory
#   7. Added: azurerm_private_endpoint.caphost_cosmos — PE for CosmosDB SQL sub-resource
#   8. Updated: module "foundry" — new inputs pass backing resource details into
#              ./modules/cognitive_foundry, which is responsible for creating per-project:
#                - RBAC role assignments (pre- and post-caphost)
#                - Project connections (cosmos, storage, search)
#                - Capability host resource
#              See module "foundry" block below for the full sequence with comments.

# =============================================================================
# DATA SOURCES (unchanged)
# =============================================================================

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

# =============================================================================
# NEW DATA SOURCES — required for inline private endpoints below.
# The existing module pattern handles PE subnet + DNS lookups internally;
# inline resources in main.tf need them explicitly.
# =============================================================================

data "azurerm_subnet" "private_endpoint" {
  name                 = var.privateEndpointSubnetName
  virtual_network_name = var.vnetName
  resource_group_name  = var.existingVnetRG
}

# DNS zones for the two new private endpoints.
# The azurerm.dns provider alias resolves zones in the hub DNS subscription,
# matching the same pattern used by all other modules in this file.

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.dnsZoneRG
  provider            = azurerm.dns
}

data "azurerm_private_dns_zone" "documents" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = var.dnsZoneRG
  provider            = azurerm.dns
}

# =============================================================================
# UNCHANGED MODULES
# =============================================================================

module "identity_usage" {
  source            = "./modules/identity_usage"
  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags
  identityName      = var.identityName

  cosmosDbAccountName = module.cosmos.cosmosDbAccountName
}

module "landingzone_network" {
  source = "./modules/landingzone_network"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags
  environmentName   = var.environmentName

  useExistingVnet = var.useExistingVnet
  vnetName        = var.vnetName
  existingVnetRG  = var.existingVnetRG

  apimSubnetName            = var.apimSubnetName
  privateEndpointSubnetName = var.privateEndpointSubnetName
  functionAppSubnetName     = var.functionAppSubnetName

  apimNsgName            = var.apimNsgName
  privateEndpointNsgName = var.privateEndpointNsgName
  functionAppNsgName     = var.functionAppNsgName
  apimRouteTableName     = var.apimRouteTableName

  vnetAddressPrefix           = var.vnetAddressPrefix
  apimSubnetPrefix            = var.apimSubnetPrefix
  privateEndpointSubnetPrefix = var.privateEndpointSubnetPrefix
  functionAppSubnetPrefix     = var.functionAppSubnetPrefix

  apimSku                  = var.apimSku
  apimV2UsePrivateEndpoint = var.apimV2UsePrivateEndpoint

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "cosmos" {
  source = "./modules/cosmos"

  resourceGroupName           = var.resourceGroupName
  location                    = var.location
  tags                        = var.tags
  cosmosDbAccountName         = var.cosmosDbAccountName
  cosmosDbPublicAccess        = var.cosmosDbPublicAccess
  cosmosDbRUs                 = var.cosmosDbRUs
  vnetName                    = var.vnetName
  existingVnetRG              = var.existingVnetRG
  privateEndpointSubnetName   = var.privateEndpointSubnetName
  cosmosDbPrivateEndpointName = var.cosmosDbPrivateEndpointName
  dnsZoneRG                   = var.dnsZoneRG
  dnsSubscriptionId           = var.dnsSubscriptionId

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "monitor" {
  source = "./modules/monitor"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  logAnalyticsName                    = var.logAnalyticsName
  applicationInsightsName             = var.applicationInsightsName
  applicationInsightsDashboardName    = var.applicationInsightsDashboardName
  funcApplicationInsightsName         = var.funcApplicationInsightsName
  funcAplicationInsightsDashboardName = var.funcAplicationInsightsDashboardName

  createAppInsightsDashboard      = var.createAppInsightsDashboard
  useAzureMonitorPrivateLinkScope = var.useAzureMonitorPrivateLinkScope

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "event_hub" {
  source = "./modules/event_hub"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  eventHubNamespaceName = var.eventHubNamespaceName
  eventHubCapacityUnits = var.eventHubCapacityUnits
  eventHubNetworkAccess = var.eventHubNetworkAccess

  eventHubPrivateEndpointName = var.eventHubPrivateEndpointName

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  enableAIGatewayPiiRedaction = var.enableAIGatewayPiiRedaction

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "openai" {
  source   = "./modules/cognitive_openai"
  for_each = var.openAiInstances

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  openAIExternalNetworkAccess   = var.openAIExternalNetworkAccess
  openAiPrivateEndpointName     = "${each.value.name}-pe"
  openAiPrivateEndpointLocation = var.location

  kind     = "OpenAI"
  sku_name = "S0"

  accountName        = each.value.name
  accountRegion      = each.value.location
  deployments        = each.value.deployments
  deploymentCapacity = var.deploymentCapacity

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "language" {
  source = "./modules/cognitive_openai"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  openAIExternalNetworkAccess = var.languageServiceExternalNetworkAccess

  accountName        = var.languageServiceName
  accountRegion      = var.location
  deployments        = []
  deploymentCapacity = null

  kind     = "TextAnalytics"
  sku_name = "S"

  openAiPrivateEndpointName     = "${var.languageServiceName}-pe"
  openAiPrivateEndpointLocation = var.location

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "content_safety" {
  source = "./modules/cognitive_openai"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  openAIExternalNetworkAccess = var.aiContentSafetyExternalNetworkAccess

  accountName        = var.aiContentSafetyName
  accountRegion      = var.location
  deployments        = []
  deploymentCapacity = null

  kind     = "ContentSafety"
  sku_name = "S0"

  openAiPrivateEndpointName     = "${var.aiContentSafetyName}-pe"
  openAiPrivateEndpointLocation = var.location

  providers = {
    azurerm.dns = azurerm.dns
  }
}

module "apim_core" {
  source = "./modules/apim_core"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  apimServiceName = var.apimServiceName
  apimSku         = var.apimSku
  apimSkuUnits    = var.apimSkuUnits

  apimNetworkType           = var.apimNetworkType
  apimV2UsePrivateEndpoint  = var.apimV2UsePrivateEndpoint
  apimV2PublicNetworkAccess = var.apimV2PublicNetworkAccess

  products     = local.products
  apis         = local.apis
  named_values = local.named_values
  backends     = local.backends

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  apimSubnetName            = var.apimSubnetName
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  applicationInsightsInstrumentationKey = module.monitor.applicationInsightsInstrumentationKey

  managed_identity_id = module.identity_usage.managed_identity_id

  eventHubNamespaceName    = var.eventHubNamespaceName
  eventHubName             = module.event_hub.eventHubName
  eventHubEndpoint         = module.event_hub.eventHubEndpoint
  eventHubConnectionString = module.event_hub.eventHubConnectionString

  entraAuth     = var.entraAuth
  entraTenantId = var.entraTenantId
  entraClientId = var.entraClientId
  entraAudience = var.entraAudience

  providers  = { azurerm.dns = azurerm.dns }
  depends_on = [module.openai]
}

module "compute_functions" {
  source = "./modules/compute_functions"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  storageAccountName       = var.storageAccountName
  storageAccountType       = "Standard_ZRS"
  functionContentShareName = var.functionContentShareName
  logicContentShareName    = var.logicContentShareName

  managed_identity_id                   = module.identity_usage.managed_identity_id
  function_managed_identity_principalId = module.identity_usage.managed_identity_principal_id
  function_managed_identity_name        = module.identity_usage.managed_identity_name

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName
  functionAppSubnetName     = var.functionAppSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  storageBlobPrivateEndpointName  = var.storageBlobPrivateEndpointName
  storageFilePrivateEndpointName  = var.storageFilePrivateEndpointName
  storageTablePrivateEndpointName = var.storageTablePrivateEndpointName
  storageQueuePrivateEndpointName = var.storageQueuePrivateEndpointName

  functionAppName = var.usageProcessingFunctionAppName
  azdserviceName  = var.usageProcessingFunctionAppName

  functionAppLogAnalyticsWorkspaceId    = module.monitor.logAnalyticsWorkspaceId
  functionAppInsightsConnectionString   = module.monitor.funcApplicationInsightsConnectionString
  functionAppInsightsInstrumentationKey = module.monitor.funcApplicationInsightsInstrumentationKey

  eventHubNamespaceName = module.event_hub.eventHubNamespaceName
  eventHubName          = module.event_hub.eventHubName

  cosmosAccountEndpoint = "https://${module.cosmos.cosmosDbAccountName}.documents.azure.com:443/"
  cosmosDatabaseName    = module.cosmos.cosmosDbDatabaseName
  cosmosContainerName   = module.cosmos.cosmosDbContainerName

  providers = { azurerm.dns = azurerm.dns }
}

module "stream_analytics" {
  source = "./modules/stream_analytics"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  jobName = "asa-${var.environmentName}"

  managedIdentityId   = module.identity_usage.managed_identity_id
  managedIdentityName = module.identity_usage.managed_identity_name

  eventHubNamespace = module.event_hub.eventHubNamespaceName
  eventHubName      = module.event_hub.eventHubName

  cosmosDbAccountName   = module.cosmos.cosmosDbAccountName
  cosmosDbDatabaseName  = module.cosmos.cosmosDbDatabaseName
  cosmosDbContainerName = module.cosmos.cosmosDbContainerName
}

module "logic_app" {
  source = "./modules/logicapp"

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  logicAppName   = var.usageProcessingLogicAppName
  azdserviceName = "usageProcessingFunctionApp"

  storageAccountName      = var.storageAccountName
  storagePrimaryAccessKey = module.compute_functions.storagePrimaryAccessKey
  fileShareName           = var.logicContentShareName

  applicationInsightsName    = var.funcApplicationInsightsName
  log_analytics_workspace_id = module.monitor.logAnalyticsWorkspaceId

  skuFamily   = "WS"
  skuName     = "WS1"
  skuSize     = "WS1"
  skuCapaicty = var.logicAppsSkuCapacityUnits
  skuTier     = "WorkflowStandard"
  isReserved  = false

  functionAppSubnetId = data.azurerm_subnet.functionapp.id

  cosmosDbAccountName         = var.cosmosDbAccountName
  cosmosDBDatabaseName        = module.cosmos.cosmosDbDatabaseName
  cosmosDBContainerConfigName = module.cosmos.cosmosDbStreamingExportConfigContainerName
  cosmosDBContainerUsageName  = module.cosmos.cosmosDbContainerName
  cosmosDBContainerPIIName    = module.cosmos.cosmosDbPiiUsageContainerName

  eventHubNamespaceName = var.eventHubNamespaceName
  eventHubName          = module.event_hub.eventHubName
  eventHubPIIName       = module.event_hub.eventHubPIIName

  apimAppInsightsName = var.applicationInsightsName
}

module "ai_search_direct" {
  source = "./modules/ai-search"

  name                = var.aiSearchName
  resource_group_name = var.resourceGroupName
  location            = var.location
  tags                = var.tags

  sku             = var.aiSearchSku
  replica_count   = var.aiSearchReplicaCount
  partition_count = var.aiSearchPartitionCount

  public_network_access_enabled = false
  local_authentication_enabled  = true
  private_endpoint_enabled      = true

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  enable_diagnostics         = true
  log_analytics_workspace_id = module.monitor.logAnalyticsWorkspaceId

  providers = {
    azurerm.dns = azurerm.dns
  }
}

# =============================================================================
# NEW: CAPABILITY HOST AI SEARCH — dedicated instance.
#
# Separate from module "ai_search_direct" (shared/direct access, local auth
# enabled) for two reasons:
#   1. Isolation: capability host indexing does not compete with the shared
#      service's replica capacity or index quotas.
#   2. Auth model: local_authentication_enabled = false enforces AAD-only
#      access, matching the AAD connection the capability host uses.
# =============================================================================

module "caphost_search" {
  source = "./modules/ai-search"

  name                = var.caphostSearchName
  resource_group_name = var.resourceGroupName
  location            = var.location
  tags                = var.tags

  sku             = var.caphostSearchSku
  replica_count   = 1
  partition_count = 1

  # AAD-only — key-based auth disabled; the capability host connects via AAD.
  public_network_access_enabled = false
  local_authentication_enabled  = false
  private_endpoint_enabled      = true

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  enable_diagnostics         = true
  log_analytics_workspace_id = module.monitor.logAnalyticsWorkspaceId

  providers = {
    azurerm.dns = azurerm.dns
  }
}

# =============================================================================
# NEW: CAPABILITY HOST BACKING RESOURCES
#
# These back the Agent Service capability host created per project inside
# module "foundry". Three services are required:
#   Storage   → file/agent storage   (storageConnections in caphost body)
#   CosmosDB  → thread storage       (threadStorageConnections in caphost body)
#   AI Search → vector store         (vectorStoreConnections in caphost body)
#               provided by module "caphost_search" above
# =============================================================================

# -----------------------------------------------------------------------------
# Storage Account — capability host file storage.
#
# Uses azapi_resource (not azurerm_storage_account) to enforce the full
# lockdown property set in a single PUT: shared key disabled, blob public
# access off, TLS 1.2 minimum, network ACLs deny-all except Azure Services.
# -----------------------------------------------------------------------------

resource "azapi_resource" "caphost_storage" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = var.caphostStorageAccountName
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resourceGroupName}"

  schema_validation_enabled = false

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_ZRS" }
    properties = {
      allowSharedKeyAccess     = false
      allowBlobPublicAccess    = false
      minimumTlsVersion        = "TLS1_2"
      publicNetworkAccess      = "Disabled"
      supportsHttpsTrafficOnly = true
      networkAcls = {
        defaultAction = "Deny"
        bypass        = ["AzureServices"]
      }
    }
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "caphost_storage_blob" {
  name                = "${var.caphostStorageAccountName}-blob-pe"
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = data.azurerm_subnet.private_endpoint.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.caphostStorageAccountName}-blob-psc"
    private_connection_resource_id = azapi_resource.caphost_storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "caphost-storage-blob-dns"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blob.id]
  }
}

# -----------------------------------------------------------------------------
# CosmosDB Account — capability host thread storage.
#
# Separate from module "cosmos" (usage/billing tracking). The Agent Service
# creates the enterprise_memory database's collections lazily at runtime
# (e.g. agent-definitions-v1 on first agent create/list). The database
# resource below is created by Terraform so its lifecycle is managed here;
# collection-level resources are intentionally omitted — see the CosmosDB SQL
# role assignment inside module "foundry" for why scope is database-level.
#
# Local auth is disabled — project MIs access via AAD only.
# -----------------------------------------------------------------------------

resource "azurerm_cosmosdb_account" "caphost_cosmos" {
  name                = var.caphostCosmosDbAccountName
  location            = var.location
  resource_group_name = var.resourceGroupName
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  local_authentication_disabled = true
  public_network_access_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_sql_database" "caphost_enterprise_memory" {
  name                = "enterprise_memory"
  resource_group_name = var.resourceGroupName
  account_name        = azurerm_cosmosdb_account.caphost_cosmos.name
}

resource "azurerm_private_endpoint" "caphost_cosmos" {
  name                = "${var.caphostCosmosDbAccountName}-pe"
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = data.azurerm_subnet.private_endpoint.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.caphostCosmosDbAccountName}-psc"
    private_connection_resource_id = azurerm_cosmosdb_account.caphost_cosmos.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "caphost-cosmos-dns"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.documents.id]
  }
}

# =============================================================================
# UPDATED: module "foundry"
#
# Six new inputs pass the capability host backing resource details into
# ./modules/cognitive_foundry. The module is responsible for the full
# per-project capability host sequence using those inputs:
#
#   STEP 1 — wait 10s after project creation for AAD MI propagation, then
#            create four pre-caphost role assignments per project MI:
#              - Cosmos DB Operator          → caphost_cosmos (control-plane access)
#              - Storage Blob Data Contributor → caphost_storage (pre-caphost data access)
#              - Search Index Data Contributor → caphost_search (index read/write)
#              - Search Service Contributor    → caphost_search (service management)
#
#   STEP 2 — wait 60s for RBAC propagation, then create three AAD-auth
#            connections per project (cosmos-caphost, storage-caphost,
#            search-caphost) pointing at the backing resource endpoints.
#
#   STEP 3 — create the capabilityHost resource per project, referencing
#            the three connection names from step 2.
#
#   STEP 4 — after the capability host exists, create two post-caphost
#            role assignments per project MI:
#              - CosmosDB SQL Data Contributor scoped to the enterprise_memory
#                database (database-level scope, not collection, because the
#                Agent Service creates collections lazily at runtime)
#              - Storage Blob Data Owner with ABAC condition restricting access
#                to containers prefixed with the project's internalId GUID
#                (the Agent Service names containers "{guid}-azureml-agent*")
# =============================================================================

module "foundry" {
  source   = "./modules/cognitive_foundry"
  for_each = var.foundryInstances

  resourceGroupName = var.resourceGroupName
  location          = var.location
  tags              = var.tags

  vnetName                  = var.vnetName
  existingVnetRG            = var.existingVnetRG
  privateEndpointSubnetName = var.privateEndpointSubnetName

  dnsZoneRG         = var.dnsZoneRG
  dnsSubscriptionId = var.dnsSubscriptionId

  foundryExternalNetworkAccess   = var.foundryExternalNetworkAccess
  foundryPrivateEndpointName     = "${each.value.name}-pe"
  foundryPrivateEndpointLocation = var.location

  sku_name                        = "S0"
  accountName                     = each.value.name
  accountRegion                   = each.value.location
  FoundryProjectManagementEnabled = try(each.value.FoundryProjectManagementEnabled, false)
  projects                        = try(each.value.projects, [])
  deployments                     = each.value.deployments

  providers = {
    azurerm.dns = azurerm.dns
  }

  # ---------------------------------------------------------------------------
  # Capability host backing resources — passed in so the module can create
  # per-project RBAC, connections, and the capability host (see sequence above).
  # ---------------------------------------------------------------------------

  enableCapabilityHost = var.enableCapabilityHost

  # CosmosDB — thread storage. Endpoint used for the connection target;
  # account ID used to scope the pre-caphost Cosmos DB Operator role assignment
  # and the post-caphost CosmosDB SQL Data Contributor role assignment.
  caphostCosmosEndpoint  = azurerm_cosmosdb_account.caphost_cosmos.endpoint
  caphostCosmosAccountId = azurerm_cosmosdb_account.caphost_cosmos.id

  # Storage — file/agent storage. Blob endpoint used for the connection target;
  # account ID used to scope the pre-caphost Storage Blob Data Contributor role
  # and the post-caphost Storage Blob Data Owner ABAC role assignment.
  caphostStorageBlobEndpoint = azapi_resource.caphost_storage.output.properties.primaryEndpoints.blob
  caphostStorageAccountId    = azapi_resource.caphost_storage.id

  # AI Search — vector store. Endpoint used for the connection target;
  # account ID used to scope the Search Index Data Contributor and
  # Search Service Contributor pre-caphost role assignments.
  caphostSearchEndpoint  = "https://${module.caphost_search.name}.search.windows.net"
  caphostSearchAccountId = module.caphost_search.id
}
