output "core_rg_name" {
  description = "Name of the core resource group."
  value       = azurerm_resource_group.main.name
}

output "core_account_id" {
  description = "Resource ID of the aif-core Foundry account."
  value       = azapi_resource.core_account.id
}

output "core_account_endpoint" {
  description = "Endpoint URL of the aif-core Foundry account."
  value       = azapi_resource.core_account.output.properties.endpoint
}

output "research_account_id" {
  description = "Resource ID of the aif-research Foundry account."
  value       = azurerm_cognitive_account.research.id
}

output "research_account_endpoint" {
  description = "Endpoint URL of the aif-research Foundry account."
  value       = azurerm_cognitive_account.research.endpoint
}

output "apim_name" {
  description = "Name of the APIM instance."
  value       = azurerm_api_management.main.name
}

output "apim_id" {
  description = "Resource ID of the APIM instance."
  value       = azurerm_api_management.main.id
}

output "apim_gateway_url" {
  description = "APIM gateway URL."
  value       = azurerm_api_management.main.gateway_url
}

output "apim_mi_principal_id" {
  description = "Principal ID of the APIM managed identity."
  value       = azurerm_api_management.main.identity[0].principal_id
}

output "apim_subscription_keys" {
  description = "Map of team name to APIM subscription primary key."
  value       = { for k, v in azurerm_api_management_subscription.team : k => v.primary_key }
  sensitive   = true
}
