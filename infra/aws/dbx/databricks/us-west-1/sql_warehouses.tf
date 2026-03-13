# =============================================================================
# Databricks Workspace SQL Warehouses
# =============================================================================

locals {
  sql_warehouses_enabled = false

  sql_warehouses = {
    analytics_ci = {
      name                      = "Analytics CI Warehouse"
      cluster_size              = "2X-Small"
      max_num_clusters          = 1
      auto_stop_mins            = 10
      enable_serverless_compute = false
      warehouse_type            = "PRO"
      enable_photon             = true
      channel = {
        name = "CHANNEL_NAME_CURRENT"
      }
      tags = {
        Environment = "shared"
        Owner       = "data-platform"
      }
      permissions = concat(
        [
          {
            principal_type   = "group"
            principal_name   = local.identity_groups.platform_admins.display_name
            permission_level = "CAN_MANAGE"
          }
        ],
        local.service_principals_enabled ? [
          {
            principal_type   = "service_principal"
            principal_name   = module.service_principals.application_ids["uat_promotion"]
            permission_level = "CAN_USE"
          }
        ] : []
      )
    }
  }
}

module "sql_warehouses" {
  source = "./modules/databricks_workspace/sql_warehouses"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled        = local.sql_warehouses_enabled
  sql_warehouses = local.sql_warehouses

  depends_on = [
    module.users_groups,
    module.service_principals,
  ]
}
