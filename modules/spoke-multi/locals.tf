locals {
  subscription_suffix = substr(sha256("${data.azurerm_client_config.current.subscription_id}-terraform"), 0, 6)

  # Short region abbreviations used in resource names.
  region_abbr = {
    eastus             = "eus"
    eastus2            = "eus2"
    westus             = "wus"
    westus2            = "wus2"
    westus3            = "wus3"
    northeurope        = "neu"
    westeurope         = "weu"
    norwayeast         = "noea"
    uksouth            = "uks"
    ukwest             = "ukw"
    australiaeast      = "aue"
    australiasoutheast = "ause"
    southeastasia      = "sea"
    eastasia           = "ea"
    swedencentral      = "swc"
  }

  spoke_rg_name      = "rg-${var.customer}-multi-${local.subscription_suffix}"
  spoke_account_name = "aif-spk-${var.customer}-${local.subscription_suffix}"
  spoke_subdomain    = local.spoke_account_name

  # Dependent resource names (only provisioned when enable_private_networking = true).
  # Storage: max 24 chars, alphanumeric only — no hyphens permitted.
  agent_storage_name = "st${replace(var.customer, "-", "")}${local.subscription_suffix}"
  agent_cosmos_name  = "cosmos-${var.customer}-${local.subscription_suffix}"
  agent_search_name  = "srch-${var.customer}-${local.subscription_suffix}"

  # Project internal GUID used to construct CosmosDB collection names and Storage
  # ABAC conditions. Azure returns the 32-char hex internalId in the project's
  # ARM response; we reformat it as a standard UUID. Falls back to a zero GUID
  # (for mock-provider tests) when the output is not yet available.
  project_id_guid = {
    for k, v in azapi_resource.team_project :
    k => try(
      format("%s-%s-%s-%s-%s",
        substr(tostring(v.output.properties.internalId), 0, 8),
        substr(tostring(v.output.properties.internalId), 8, 4),
        substr(tostring(v.output.properties.internalId), 12, 4),
        substr(tostring(v.output.properties.internalId), 16, 4),
        substr(tostring(v.output.properties.internalId), 20, 12)
      ),
      "00000000-0000-0000-0000-000000000000"
    )
  }

  # All hub + research models formatted for jsonencode() in connection metadata.
  # Must be jsonencode()'d — a raw HCL object creates the resource but Foundry
  # won't surface the models in the project UI.
  all_models = concat(
    [for m in var.core_models : {
      name = m.name
      properties = {
        model = {
          name    = m.name
          version = ""
          format  = m.format
        }
      }
    }],
    [for m in var.research_models : {
      name = m.name
      properties = {
        model = {
          name    = m.name
          version = ""
          format  = m.format
        }
      }
    }]
  )

  common_tags = {
    environment = var.environment
    workload    = var.workload
    customer    = var.customer
    managed_by  = "terraform"
  }
}
