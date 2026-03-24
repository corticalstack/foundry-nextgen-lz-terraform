provider "azurerm" {
  use_oidc             = true
  storage_use_azuread  = true

  features {
    api_management {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azapi" {
  use_oidc = true
}
