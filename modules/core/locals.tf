locals {
  # 6-character hex suffix derived from SHA-256 of subscription ID.
  # Matches the Python convention used in the Jupyter notebooks:
  #   hashlib.sha256(subscription_id.encode()).hexdigest()[:6]
  subscription_suffix = substr(sha256("${data.azurerm_client_config.current.subscription_id}-terraform"), 0, 6)

  # Short region abbreviations used in resource names.
  region_abbr = {
    eastus            = "eus"
    eastus2           = "eus2"
    westus            = "wus"
    westus2           = "wus2"
    westus3           = "wus3"
    northeurope       = "neu"
    westeurope        = "weu"
    norwayeast        = "noea"
    uksouth           = "uks"
    ukwest            = "ukw"
    australiaeast     = "aue"
    australiasoutheast = "ause"
    southeastasia     = "sea"
    eastasia          = "ea"
    swedencentral     = "swc"
  }

  # Computed resource names
  core_rg_name          = "rg-${var.customer}-core-${local.subscription_suffix}"
  core_account_name     = "aif-core-${var.customer}-${local.subscription_suffix}"
  core_subdomain        = local.core_account_name
  research_account_name = "aif-research-${var.customer}-${local.subscription_suffix}"
  research_subdomain    = local.research_account_name
  apim_name             = "apim-${var.customer}-${local.subscription_suffix}"

  # Admin capability host backing resources (conditional: enable_private_networking = true)
  # Storage: max 24 chars, alphanumeric only — no hyphens permitted.
  core_storage_name = "stcore${replace(var.customer, "-", "")}${local.subscription_suffix}"
  core_cosmos_name  = "cosmos-core-${var.customer}-${local.subscription_suffix}"
  core_search_name  = "srch-core-${var.customer}-${local.subscription_suffix}"

  # Admin project internal GUID — used to scope CosmosDB collections and Storage ABAC.
  # Falls back to zero GUID until known after apply.
  admin_project_id_guid = try(
    format("%s-%s-%s-%s-%s",
      substr(tostring(azapi_resource.admin_project[0].output.properties.internalId), 0, 8),
      substr(tostring(azapi_resource.admin_project[0].output.properties.internalId), 8, 4),
      substr(tostring(azapi_resource.admin_project[0].output.properties.internalId), 12, 4),
      substr(tostring(azapi_resource.admin_project[0].output.properties.internalId), 16, 4),
      substr(tostring(azapi_resource.admin_project[0].output.properties.internalId), 20, 12)
    ),
    "00000000-0000-0000-0000-000000000000"
  )

  common_tags = {
    environment = var.environment
    workload    = var.workload
    customer    = var.customer
    managed_by  = "terraform"
  }
}
