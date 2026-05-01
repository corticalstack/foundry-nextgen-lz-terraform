module "core" {
  source = "../../modules/core"

  environment               = var.environment
  location                  = var.location
  customer                  = var.customer
  publisher_email           = var.publisher_email
  publisher_name            = var.publisher_name
  deployer_principal_id     = local.deployer_principal_id
  core_models               = var.core_models
  research_models           = var.research_models
  teams                     = var.teams
  enable_private_networking = var.enable_private_networking
  private_networking        = local.private_networking_effective
  dns_zone_ids              = local.dns_zone_ids
}

module "spoke_multi" {
  source = "../../modules/spoke-multi"

  environment                = var.environment
  location                   = var.location
  customer                   = var.customer
  deployer_principal_id      = local.deployer_principal_id
  teams                      = var.teams
  apim_gateway_url           = module.core.apim_gateway_url
  apim_subscription_keys     = module.core.apim_subscription_keys
  core_models                = var.core_models
  research_models            = var.research_models
  enable_private_networking  = var.enable_private_networking
  private_networking         = local.private_networking_effective
  dns_zone_ids               = local.dns_zone_ids
  log_analytics_workspace_id = module.core.log_analytics_workspace_id
}
