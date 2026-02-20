# =============================================================================
# Databricks Identity Configuration
# =============================================================================

locals {
  # Define account-level groups keyed by stable IDs.
  # Keep this map empty when no additional groups are needed.
  identity_groups = {
    # platform_admins = {
    #   display_name          = "Platform Admins"
    #   roles                 = ["account_admin"]
    #   workspace_permissions = ["ADMIN"]
    #   entitlements = {
    #     allow_cluster_create  = true
    #     databricks_sql_access = true
    #     workspace_access      = true
    #   }
    # }
  }

  # Define account-level users keyed by stable IDs.
  # NOTE: `var.admin_user` workspace assignment is currently managed by
  # `module.user_assignment` in `main.tf`.
  identity_users = {
    # jane_doe = {
    #   user_name              = "jane.doe@example.com"
    #   groups                 = ["platform_admins"]
    #   roles                  = ["account_admin"]
    #   workspace_permissions  = ["ADMIN"]
    #   entitlements = {
    #     databricks_sql_access = true
    #     workspace_access      = true
    #   }
    # }
  }

  # FUTURE NOTE:
  # The bootstrap `admin_user` is intended only for initial account/workspace
  # provisioning (managed by `module.user_assignment` in `main.tf`).
  # If needed later, uncomment this filter and pass `local.managed_identity_users`
  # to this module to ensure `admin_user` is excluded from identity management.
  #
  # bootstrap_admin_user = lower(trimspace(var.admin_user))
  # managed_identity_users = {
  #   for user_key, user in local.identity_users :
  #   user_key => user
  #   if lower(trimspace(user.user_name)) != local.bootstrap_admin_user
  # }
}

module "users_groups" {
  source = "./modules/databricks_account/users_groups"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  workspace_id = module.databricks_mws_workspace.workspace_id
  groups       = local.identity_groups
  users        = local.identity_users

  depends_on = [module.databricks_mws_workspace]
}
