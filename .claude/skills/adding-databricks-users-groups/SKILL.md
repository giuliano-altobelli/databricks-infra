---
name: adding-databricks-users-groups
description: Use when adding, modifying, or removing Databricks users, groups, memberships, entitlements, or Unity Catalog group grants in the databricks-infra Terraform project
---

# Adding Databricks Users & Groups

## Overview

All Databricks identity (users, groups, memberships, roles, entitlements, workspace assignments) is managed via locals in `identify.tf`, consumed by the `users_groups` module.

## File & Location

**Edit only:** `infra/aws/dbx/databricks/us-west-1/identify.tf`

- Users go in `local.identity_users`
- Groups go in `local.identity_groups`
- Unity Catalog grants go in `local.unity_catalog_group_catalog_privileges`

The `module "users_groups"` call already passes these locals to the module. No other files need editing.

## Group Role Distinction

This module supports two common group patterns:

- **Plain group** (no account-wide admin role): omit `roles` (or set `roles = []`).
- **Account admin group**: set `roles = ["account_admin"]`.

When creating a new group, **ask the user** whether the group needs account admin privileges. If the user says no, leave `roles` empty (omit the attribute).

What changes between them:

- `roles = ["account_admin"]` grants account-wide Databricks admin capability to group members.
- `workspace_permissions` (e.g. `["ADMIN"]` or `["USER"]`) are scoped to `workspace_id` for this module instance.
- Unity Catalog privileges are not managed by this module directly. They are granted separately via `unity_catalog_group_catalog_privileges`.

## User Schema

```hcl
identity_users = {
  <stable_key> = {
    user_name             = string           # required - email address
    display_name          = optional(string)  # defaults to null
    active                = optional(bool)    # defaults to null
    force                 = optional(bool)    # true to adopt pre-existing user
    groups                = optional(set)     # keys from identity_groups
    roles                 = optional(set)     # e.g. ["account_admin"]
    workspace_permissions = optional(set)     # "ADMIN" or "USER" only
    entitlements          = optional(object)  # see Entitlements below
  }
}
```

**Stable key**: lowercase, no spaces (e.g. `giuliano`, `jane_doe`). This key is used as the Terraform `for_each` key - changing it destroys and recreates.

## Group Schema

```hcl
identity_groups = {
  <stable_key> = {
    display_name          = string           # required - human-readable name
    roles                 = optional(set)     # e.g. ["account_admin"] - ASK USER
    workspace_permissions = optional(set)     # "ADMIN" or "USER" only
    entitlements          = optional(object)  # see Entitlements below
  }
}
```

## Entitlements Object

```hcl
entitlements = {
  allow_cluster_create       = optional(bool)
  allow_instance_pool_create = optional(bool)
  databricks_sql_access      = optional(bool)
  workspace_access           = optional(bool)
  workspace_consume          = optional(bool)  # MUTUALLY EXCLUSIVE - see below
}
```

**Constraint:** `workspace_consume` CANNOT be `true` when `workspace_access` or `databricks_sql_access` is `true`. Terraform `validate` will fail.

## Unity Catalog Grants (Groups Only)

When adding a group that needs catalog privileges, also add to `local.unity_catalog_group_catalog_privileges`:

```hcl
unity_catalog_group_catalog_privileges = {
  platform_admins = ["ALL_PRIVILEGES"]
  # new_group_key = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
}
```

Key must match a key in `identity_groups`.

## Quick Reference: Common Patterns

| Scenario | What to set |
|----------|------------|
| Basic user in existing group | `user_name`, `groups`, `entitlements` |
| Admin user | Add `roles = ["account_admin"]` and/or `workspace_permissions = ["ADMIN"]` |
| Adopt pre-existing user | Add `force = true` |
| New admin group | Create group with `roles = ["account_admin"]`, `workspace_permissions = ["ADMIN"]`, add catalog grants |
| New read-only group | Create group with `workspace_permissions = ["USER"]`, catalog privileges `["USE_CATALOG", "USE_SCHEMA", "SELECT"]` |

## Validation Rules

1. **Group references**: Every key in `users[*].groups` MUST exist in `identity_groups`. Missing keys cause a hard-fail precondition error.
2. **Workspace permissions**: Only `"ADMIN"` or `"USER"` are valid values.
3. **Entitlements mutual exclusion**: `workspace_consume = true` is incompatible with `workspace_access = true` or `databricks_sql_access = true`.

## Example: Add a User to Existing Group

```hcl
# In local.identity_users, add:
jane = {
  user_name = "jane@example.com"
  force     = true
  groups    = ["platform_admins"]
  entitlements = {
    allow_cluster_create  = true
    databricks_sql_access = true
    workspace_access      = true
  }
}
```

## Example: Add a New Group + User

```hcl
# 1. In local.identity_groups, add:
analytics_users = {
  display_name          = "Analytics Users"
  workspace_permissions = ["USER"]
  entitlements = {
    databricks_sql_access = true
    workspace_access      = true
  }
}

# 2. In local.identity_users, add:
bob = {
  user_name = "bob@example.com"
  groups    = ["analytics_users"]
  entitlements = {
    databricks_sql_access = true
    workspace_access      = true
  }
}

# 3. Optionally in local.unity_catalog_group_catalog_privileges, add:
analytics_users = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| User references a group key that doesn't exist | Add the group to `identity_groups` first |
| Setting `workspace_consume = true` with `workspace_access = true` | These are mutually exclusive - pick one |
| Editing module files instead of `identify.tf` | All identity config lives in `identify.tf` locals only |
| Using `workspace_permissions = ["Admin"]` | Must be uppercase: `"ADMIN"` or `"USER"` |
| Changing a stable key (e.g. renaming `giuliano` to `giuliano_a`) | Destroys and recreates the resource - use same key |
| Assuming new group needs `roles = ["account_admin"]` | Ask the user first - most groups don't need account admin |
