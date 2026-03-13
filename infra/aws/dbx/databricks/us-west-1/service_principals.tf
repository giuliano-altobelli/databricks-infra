locals {
  service_principals_enabled = false

  service_principals = {
    uat_promotion = {
      display_name    = "UAT Promotion SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
      entitlements = {
        databricks_sql_access = true
      }
    }

    workspace_agent = {
      display_name    = "Workspace Agent SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_access = true
      }
    }
  }
}

module "service_principals" {
  source = "./modules/databricks_identity/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  enabled            = local.service_principals_enabled
  workspace_id       = local.workspace_id
  service_principals = local.service_principals

  depends_on = [module.unity_catalog_metastore_assignment]
}
