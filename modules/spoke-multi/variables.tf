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
  description = "Primary Azure region for spoke resources (e.g. eastus2)."
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

variable "deployer_principal_id" {
  type        = string
  description = "Object ID of the identity running terraform apply."
}

variable "teams" {
  type        = list(string)
  description = "Team identifiers. One project and one APIM connection is created per team."
  validation {
    condition     = length(var.teams) >= 1 && length(var.teams) <= 10
    error_message = "teams must have between 1 and 10 entries."
  }
}

variable "apim_gateway_url" {
  type        = string
  description = "APIM gateway URL from the core module output."
}

variable "apim_subscription_keys" {
  type        = map(string)
  description = "Map of team name to APIM subscription primary key."
  sensitive   = true
}

variable "core_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
  description = "Core model list — used to populate connection metadata."
}

variable "research_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
  description = "Research model list — used to populate connection metadata."
}

variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "When true, configures spoke resources for private networking (disabled public access, network injections, private endpoints, dependent resources)."
}

variable "private_networking" {
  type = object({
    vnet_id                    = string
    private_endpoint_subnet_id = string
    agent_subnet_id            = string
    spoke_agent_subnet_id      = string
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
