locals {
  deployer_principal_id = data.azurerm_client_config.current.object_id

  common_tags = {
    environment = var.environment
    customer    = var.customer
    managed_by  = "terraform"
  }

  # When private_networking is supplied, use it (BYO VNet mode).
  # Otherwise, compute from the Terraform-managed VNet resources.
  # Null when enable_private_networking = false.
  private_networking_effective = var.private_networking != null ? var.private_networking : (
    var.enable_private_networking ? {
      vnet_id                    = one(azurerm_virtual_network.main[*].id)
      private_endpoint_subnet_id = one(azurerm_subnet.pe[*].id)
      agent_subnet_id            = one(azurerm_subnet.agents[*].id)
      spoke_agent_subnet_id      = one(azurerm_subnet.agents_spoke[*].id)
      apim_subnet_id             = one(azurerm_subnet.apim[*].id)
      jump_vm_subnet_id          = one(azurerm_subnet.jump[*].id)
      bastion_subnet_id          = one(azurerm_subnet.bastion[*].id)
    } : null
  )
}
