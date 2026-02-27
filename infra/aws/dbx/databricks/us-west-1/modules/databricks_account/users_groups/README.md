# databricks_account/users_groups

Manages account-level users, groups, memberships, principal roles, workspace permission assignments, and workspace entitlements for a single target workspace.

## Provider Contract

This module requires two Databricks provider aliases to be passed by the caller:

- `databricks.mws`: account-level provider (for users/groups/memberships/roles/workspace assignments)
- `databricks.workspace`: workspace-level provider (for `databricks_entitlements`)

## Group Role Distinction

This module supports two common group patterns:

- Plain group (no account-wide admin role): omit `roles` (or set `roles = []`).
- Account admin group: set `roles = ["account_admin"]`.

What changes between them:

- `roles = ["account_admin"]` grants account-wide Databricks admin capability to group members.
- `workspace_permissions` (for example `["ADMIN"]` or `["USER"]`) are scoped to `workspace_id` for this module instance.
- Unity Catalog privileges are not managed by this module directly. They are granted separately (for example via `databricks_grant`) to the group's `display_name`.

## Existing User Handling (`force`)

- `users[*].force` is optional.
- Use `force = true` when Terraform must reconcile or adopt a pre-existing Databricks user in account identity management.
- If omitted, provider default behavior is used.

### Plain Group Example

```hcl
groups = {
  platform_admins = {
    display_name          = "Platform Admins"
    workspace_permissions = ["ADMIN"]
    entitlements = {
      allow_cluster_create  = true
      databricks_sql_access = true
      workspace_access      = true
    }
  }
}

users = {
  giuliano = {
    user_name = "giulianoaltobelli@gmail.com"
    force     = true
    groups    = ["platform_admins"]
  }
}
```

### Account Admin Group Example

```hcl
groups = {
  platform_admins = {
    display_name = "Platform Admins"
    roles        = ["account_admin"]
  }
}

users = {
  giuliano = {
    user_name = "giulianoaltobelli@gmail.com"
    groups    = ["platform_admins"]
  }
}
```

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
