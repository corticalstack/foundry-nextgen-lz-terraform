variable "environment" {
  type        = string
  description = "Deployment environment."
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, prod."
  }
}

variable "location" {
  type        = string
  description = "Primary Azure region for hub resources (e.g. eastus2)."
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "northeurope", "westeurope", "norwayeast",
      "uksouth", "ukwest",
      "australiaeast", "australiasoutheast",
      "southeastasia", "eastasia",
      "swedencentral",
    ], var.location)
    error_message = "location must be a known Azure region name (lowercase, no spaces)."
  }
}

variable "workload" {
  type        = string
  description = "Workload identifier used in resource tags."
  default     = "foundry"
}

variable "customer" {
  type        = string
  description = "Short customer slug included in all resource names and tags (e.g. 'contoso', 'fabrikam'). Lowercase alphanumeric and hyphens only. Set in private.auto.tfvars — never commit customer-specific values."
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer))
    error_message = "customer must be lowercase alphanumeric and hyphens only."
  }
}

variable "research_location" {
  type        = string
  description = "Azure region for the research account (aif-research). Defaults to norwayeast where o3/reasoning models are available with GlobalStandard SKU."
  default     = "norwayeast"
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "northeurope", "westeurope", "norwayeast",
      "uksouth", "ukwest",
      "australiaeast", "australiasoutheast",
      "southeastasia", "eastasia",
      "swedencentral",
    ], var.research_location)
    error_message = "research_location must be a known Azure region name (lowercase, no spaces)."
  }
}

variable "publisher_email" {
  type        = string
  description = "APIM publisher email address."
}

variable "publisher_name" {
  type        = string
  description = "APIM publisher display name."
}

variable "deployer_principal_id" {
  type        = string
  description = "Object ID of the identity running terraform apply. Sourced from data.azurerm_client_config.current.object_id at the environment root."
}

variable "project_admin_principals" {
  type = list(object({
    object_id      = string
    principal_type = optional(string, "User")
  }))
  default     = []
  description = <<-EOT
    Principals to grant 'Azure AI Project Manager' at the admin project resource scope.
    Required for portal users to invoke agents in the Build pane / playground —
    subscription-level 'Azure AI User' does NOT satisfy nextgen Foundry's project-scoped
    data-plane auth, so without an entry here those users see HTTP 403 on
    Agents_Wildcard_Get and the agent UI returns a generic error.

    Each entry:
      object_id      — Entra ID object ID of a user, group, or service principal.
      principal_type — One of 'User', 'Group', 'ServicePrincipal'. Defaults to 'User'.

    See 99-docs/core-account-admin-project-setup.md §12 for rationale and the
    diagnostic-log signature this RBAC clears.
  EOT
}

variable "core_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
  description = "Model deployments for the core account (aif-core)."
  validation {
    condition     = length(var.core_models) >= 1
    error_message = "At least one core model must be specified."
  }
}

variable "research_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
  description = "Model deployments for the research hub account (aif-research, Norway East)."
  validation {
    condition     = length(var.research_models) >= 1
    error_message = "At least one research model must be specified."
  }
}

variable "teams" {
  type        = list(string)
  description = "Team identifiers. One APIM subscription is created per team."
  validation {
    condition     = length(var.teams) >= 1 && length(var.teams) <= 10
    error_message = "teams must have between 1 and 10 entries."
  }
}

variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "When true, configures hub resources for private networking (disabled public access, private endpoints, APIM Internal mode)."
}

variable "private_networking" {
  type = object({
    vnet_id                    = string
    private_endpoint_subnet_id = string
    agent_subnet_id            = string
    apim_subnet_id             = string
    jump_vm_subnet_id          = string
    bastion_subnet_id          = string
  })
  default     = null
  description = "BYO VNet subnet IDs. Required when enable_private_networking = true."
}

variable "dns_zone_ids" {
  type = object({
    cognitive_services = string
    openai             = string
    services_ai        = string
    search             = string
    documents          = string
    blob               = string
    file               = string
    apim               = string
  })
  default     = null
  description = "Private DNS zone resource IDs created at the environment root. Required when enable_private_networking = true."
}
