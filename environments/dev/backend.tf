# Storage account name is never hardcoded here.
# Inject it at init time:
#   terraform init -backend-config="storage_account_name=stterraformstate<suffix>"
#
# For local development without the bootstrap storage account, comment out the
# backend block below and run: terraform init -reconfigure
# Restore it (and re-init with -backend-config) before a shared/CI deployment.

# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-terraform-state"
#     container_name       = "dev-tfstate"
#     key                  = "foundry-hub-spoke.tfstate"
#     use_oidc             = true
#     use_azuread_auth     = true
#   }
# }
