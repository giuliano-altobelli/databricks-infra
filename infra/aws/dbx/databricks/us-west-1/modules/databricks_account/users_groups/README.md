# databricks_account/users_groups

Manages account-level users, groups, memberships, principal roles, workspace permission assignments, and workspace entitlements for a single target workspace.

## Provider Contract

This module requires two Databricks provider aliases to be passed by the caller:

- `databricks.mws`: account-level provider (for users/groups/memberships/roles/workspace assignments)
- `databricks.workspace`: workspace-level provider (for `databricks_entitlements`)

## Usage

```hcl
module "users_groups" {
  source = "./modules/databricks_account/users_groups"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  workspace_id = module.workspace.workspace_id

  groups = {
    data_platform_admins = {
      display_name           = "Data Platform Admins"
      roles                  = ["account_admin"]
      workspace_permissions  = ["ADMIN"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
    analytics_users = {
      display_name          = "Analytics Users"
      workspace_permissions = ["USER"]
      entitlements = {
        databricks_sql_access = true
        workspace_access      = true
      }
    }
  }

  users = {
    alice = {
      user_name              = "alice@example.com"
      display_name           = "Alice Example"
      groups                 = ["data_platform_admins"]
      roles                  = ["account_admin"]
      workspace_permissions  = ["ADMIN"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
    bob = {
      user_name              = "bob@example.com"
      groups                 = ["analytics_users"]
      workspace_permissions  = ["USER"]
    }
  }
}
```

## Notes

- Exactly one workspace is targeted per module invocation.
- Entitlements are authoritative for principals where `entitlements` is provided.
- Create one module instance per workspace when managing multiple workspaces.
