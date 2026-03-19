# =============================================================================
# Databricks Identity Configuration
# =============================================================================

locals {
  # Define additional account-level groups keyed by stable IDs.
  identity_groups = {
    platform_admins = {
      display_name          = "Sandbox Platform Admins"
      workspace_permissions = ["ADMIN"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
  }

  # Existing human users must already be provisioned by Okta SCIM before
  # Terraform runs. Baseline workspace access continues to flow from Okta SCIM
  # and `okta-databricks-users`, while `module.user_assignment` in `main.tf`
  # preserves bootstrap admin access during this rollout.
  identity_users = {
    giuliano = {
      user_name = "giulianoaltobelli@gmail.com"
      groups    = ["platform_admins"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
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

  # Unity Catalog grants move to phase 2 and phase 3 of this rollout.
}

module "users_groups" {
  source = "./modules/databricks_identity/users_groups"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  workspace_id = local.workspace_id
  groups       = local.identity_groups
  users        = local.identity_users

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.user_assignment,
  ]
}
