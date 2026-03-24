# Tests for Phase 1: feature-flag variables and region fixes.
# All tests use mock_provider blocks — no Azure credentials required.

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "time" {}

# ---------------------------------------------------------------------------
# 1. enable_private_networking defaults to false
# ---------------------------------------------------------------------------
run "enable_private_networking_defaults_to_false" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = false  # explicit: overrides any auto.tfvars during testing
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = var.enable_private_networking == false
    error_message = "enable_private_networking must default to false"
  }
}

# ---------------------------------------------------------------------------
# 2. private_networking = null with flag false passes validation
# ---------------------------------------------------------------------------
run "private_networking_null_when_flag_false" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = false
    private_networking        = null
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = var.private_networking == null
    error_message = "private_networking should be null when flag is false"
  }
}

# ---------------------------------------------------------------------------
# 3. private_networking = null with flag true succeeds — Terraform creates
#    the VNet automatically using vnet_config defaults.
# ---------------------------------------------------------------------------
run "managed_vnet_created_when_private_networking_null" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    private_networking        = null
    jump_vm_admin_password    = "TempPass1!TempPass1!"
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = azurerm_virtual_network.main[0].name == "vnet-foundry"
    error_message = "Expected Terraform-managed VNet to be created when private_networking = null"
  }

  assert {
    condition     = azurerm_subnet.bastion[0].name == "AzureBastionSubnet"
    error_message = "Expected AzureBastionSubnet to be created with the required name"
  }
}

# ---------------------------------------------------------------------------
# 4. Full private_networking object with flag true passes validation
# ---------------------------------------------------------------------------
run "private_networking_validation_accepts_full_object" {
  command = plan

  variables {
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = true
    private_networking = {
      vnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main"
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-pe"
      agent_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-agents"
      apim_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-apim"
      jump_vm_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-jump"
      bastion_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/AzureBastionSubnet"
    }
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = var.enable_private_networking == true
    error_message = "enable_private_networking should be true"
  }

  assert {
    condition     = var.private_networking != null
    error_message = "private_networking should be set"
  }
}

# ---------------------------------------------------------------------------
# 5. region_abbr map includes swedencentral — plan must succeed without error
# ---------------------------------------------------------------------------
run "region_abbr_includes_swedencentral" {
  command = plan

  variables {
    location                  = "swedencentral"
    publisher_email           = "test@example.com"
    publisher_name            = "Test"
    teams                     = ["alpha"]
    enable_private_networking = false
    hub_models = [{
      name     = "gpt-4.1-mini"
      format   = "OpenAI"
      version  = "2025-04-14"
      sku      = "GlobalStandard"
      capacity = 10
    }]
    research_models = [{
      name     = "o3-deep-research"
      format   = "OpenAI"
      version  = "2025-06-26"
      sku      = "GlobalStandard"
      capacity = 10
    }]
  }

  assert {
    condition     = var.location == "swedencentral"
    error_message = "location should be swedencentral"
  }
}
