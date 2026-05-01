output "apim_gateway_url" {
  description = "APIM gateway URL."
  value       = module.core.apim_gateway_url
}

output "core_endpoint" {
  description = "Endpoint URL of the aif-core Foundry account."
  value       = module.core.core_account_endpoint
}

output "research_endpoint" {
  description = "Endpoint URL of the aif-research Foundry account."
  value       = module.core.research_account_endpoint
}

output "spoke_account_name" {
  description = "Name of the shared aif-spoke-multi Foundry account."
  value       = module.spoke_multi.spoke_account_name
}

output "project_endpoints" {
  description = "Map of team name to Foundry project endpoint URL."
  value       = module.spoke_multi.project_endpoints
}

output "bastion_name" {
  description = "Name of the Azure Bastion host (only set when enable_private_networking = true)."
  value       = var.enable_private_networking ? azurerm_bastion_host.main[0].name : null
}

output "jump_vm_name" {
  description = "Name of the jump VM (only set when enable_private_networking = true)."
  value       = var.enable_private_networking ? azurerm_windows_virtual_machine.jump_vm[0].name : null
}

output "jump_vm_resource_id" {
  description = "Azure resource ID of the jump VM — use for portal navigation and Bastion connect (only set when enable_private_networking = true)."
  value       = var.enable_private_networking ? azurerm_windows_virtual_machine.jump_vm[0].id : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the shared Log Analytics workspace receiving Foundry account and storage diagnostics."
  value       = module.core.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the shared Log Analytics workspace (handy for portal navigation)."
  value       = module.core.log_analytics_workspace_name
}
