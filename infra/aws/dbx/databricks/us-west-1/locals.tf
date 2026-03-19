locals {
  create_workspace = var.workspace_source == "create"

  workspace_host = local.create_workspace ? try(module.databricks_mws_workspace[0].workspace_url, null) : coalesce(
    var.existing_workspace_host,
    try(module.databricks_mws_workspace[0].workspace_url, null)
  )

  workspace_id = local.create_workspace ? try(module.databricks_mws_workspace[0].workspace_id, null) : coalesce(
    var.existing_workspace_id,
    try(module.databricks_mws_workspace[0].workspace_id, null)
  )

  is_enterprise       = var.pricing_tier == "ENTERPRISE"
  use_managed_network = var.network_configuration == "managed"

  enable_enterprise_infra                   = local.is_enterprise && local.create_workspace
  enable_customer_managed_network           = local.enable_enterprise_infra && !local.use_managed_network
  enable_customer_managed_keys              = local.enable_enterprise_infra
  enable_privatelink                        = local.enable_customer_managed_network && var.network_configuration == "isolated"
  enable_network_policy                     = local.enable_enterprise_infra
  enable_network_connectivity_configuration = local.enable_enterprise_infra
  enable_restrictive_root_bucket            = local.enable_enterprise_infra
  enable_disable_legacy_settings            = local.is_enterprise

  # Temporary compatibility alias for disabled single-catalog consumers.
  catalog_name = try(module.governed_catalogs["personal"].catalog_name, null)
}
