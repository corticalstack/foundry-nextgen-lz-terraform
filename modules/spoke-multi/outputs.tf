output "spoke_rg_name" {
  description = "Name of the spoke-multi resource group."
  value       = azurerm_resource_group.main.name
}

output "spoke_account_name" {
  description = "Name of the shared aif-spoke-multi Foundry account."
  value       = azapi_resource.spoke_account.name
}

output "spoke_account_endpoint" {
  description = "Endpoint URL of the shared aif-spoke-multi Foundry account."
  value       = azapi_resource.spoke_account.output.properties.endpoint
}

output "project_names" {
  description = "Map of team name to Foundry project name."
  value       = { for k, v in azapi_resource.team_project : k => v.name }
}

output "project_endpoints" {
  description = "Map of team name to Foundry project endpoint URL."
  value = {
    for k, v in azapi_resource.team_project : k =>
    "https://${local.spoke_account_name}.services.ai.azure.com/api/projects/${v.name}"
  }
}
