variable "environment" {
  type    = string
  default = "dev"
}

variable "customer" {
  type        = string
  description = "Short customer slug included in all resource names and tags (e.g. 'contoso', 'fabrikam'). Lowercase alphanumeric and hyphens only. Set in private.auto.tfvars — never commit customer-specific values."
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer))
    error_message = "customer must be lowercase alphanumeric and hyphens only."
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "publisher_email" {
  type = string
}

variable "publisher_name" {
  type = string
}

variable "core_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
}

variable "research_models" {
  type = list(object({
    name     = string
    format   = string
    version  = string
    sku      = string
    capacity = number
  }))
}

variable "teams" {
  type = list(string)
}

variable "enable_private_networking" {
  type        = bool
  default     = false
  description = <<-EOT
    When false (default), all PaaS resources are publicly accessible and no
    networking resources are created — behaviour is identical to the baseline
    deployment.

    When true, all PaaS resources are deployed with publicNetworkAccess = Disabled,
    8 private DNS zones are created and linked to the caller-supplied VNet, private
    endpoints are placed in the caller-supplied subnet, APIM switches to Internal
    VNet mode, and a Windows Server 2022 jump VM with Azure Bastion is deployed for
    validation.

    NOTE: All networking resources (VNet, subnets, NSGs) must exist in the SAME
    region as var.location — cross-region private endpoints are not supported.
  EOT
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
  description = <<-EOT
    Optional BYO VNet configuration. When null (default) and enable_private_networking = true,
    Terraform creates a VNet and all required subnets automatically using var.vnet_config CIDRs.

    Supply this only if you want to use a pre-existing VNet. All subnets must already exist
    and be correctly delegated:
      - private_endpoint_subnet_id: private_endpoint_network_policies = "Disabled"
      - agent_subnet_id: delegated to Microsoft.App/environments
      - apim_subnet_id: delegated to Microsoft.ApiManagement/service
      - bastion_subnet_id: MUST be named exactly "AzureBastionSubnet" (/26 or larger)
  EOT
}

variable "vnet_config" {
  type = object({
    address_space       = list(string)
    subnet_pe           = string
    subnet_agents       = string
    subnet_apim         = string
    subnet_jump         = string
    subnet_bastion      = string
    subnet_agents_spoke = string
  })
  default = {
    address_space        = ["10.0.0.0/16"]
    subnet_pe            = "10.0.0.0/24"
    subnet_agents        = "10.0.1.0/24"
    subnet_apim          = "10.0.2.0/24"
    subnet_jump          = "10.0.3.0/24"
    subnet_bastion       = "10.0.4.0/26"
    subnet_agents_spoke  = "10.0.5.0/24"
  }
  description = <<-EOT
    CIDR configuration for the Terraform-managed VNet, used when enable_private_networking = true
    and private_networking = null (default). Ignored when private_networking is supplied.

    subnet_bastion must be /26 or larger — Azure enforces this for AzureBastionSubnet.
    All CIDRs must fall within address_space and must not overlap.
  EOT
}

variable "jump_vm_admin_username" {
  type        = string
  default     = "azureadmin"
  description = "Administrator username for the jump VM."
}

variable "jump_vm_admin_password" {
  type        = string
  sensitive   = true
  default     = null
  description = <<-EOT
    Administrator password for the jump VM. Required when enable_private_networking = true.
    Must meet Azure password complexity: 12+ chars, upper, lower, digit, special char.
    Set in terraform.tfvars (gitignored) — never commit this value.
  EOT
}
