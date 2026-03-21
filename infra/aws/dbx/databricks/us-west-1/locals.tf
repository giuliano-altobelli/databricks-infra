locals {
  workspace_host = module.databricks_mws_workspace.workspace_url
  workspace_id   = module.databricks_mws_workspace.workspace_id

  is_enterprise       = var.pricing_tier == "ENTERPRISE"
  use_managed_network = var.network_configuration == "managed"

  enable_enterprise_infra                   = local.is_enterprise
  enable_customer_managed_network           = local.enable_enterprise_infra && !local.use_managed_network
  enable_customer_managed_keys              = local.enable_enterprise_infra
  enable_privatelink                        = local.enable_customer_managed_network && var.network_configuration == "isolated"
  enable_network_policy                     = local.enable_enterprise_infra
  enable_network_connectivity_configuration = local.enable_enterprise_infra
  enable_restrictive_root_bucket            = local.enable_enterprise_infra
  enable_disable_legacy_settings            = local.is_enterprise

  # Temporary compatibility alias for disabled single-catalog consumers.
  catalog_name = null
}
