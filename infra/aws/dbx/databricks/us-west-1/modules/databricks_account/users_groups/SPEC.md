# Module Spec

## Summary

- **Module name**: `databricks_account/users_groups`
- **One-liner**: Manage Databricks account users/groups plus memberships, roles, workspace assignments, and workspace entitlements.

## Scope

- In scope:
  - Account-level `databricks_user` and `databricks_group`
  - User-to-group membership management
  - Account role attachments for users and groups
  - Workspace permission assignments for users and groups
  - Workspace entitlements for users and groups (authoritative when provided)
- Out of scope:
  - Service principals
  - Multi-workspace fan-out in a single module instance

## Interfaces

- Required inputs:
  - Provider aliases: `databricks.mws` and `databricks.workspace`
- Optional inputs:
  - `enabled`, `workspace_id`, `prevent_destroy`, `allow_empty_groups`, `users`, `groups`
- Outputs:
  - `user_ids`, `group_ids`, `membership_ids`, `membership_keys`, `user_role_ids`, `group_role_ids`, `workspace_assignment_ids`, `entitlements_ids`

## Provider Context

- Provider(s):
  - `databricks.mws` for account-scoped identity/roles/workspace assignment resources
  - `databricks.workspace` for `databricks_entitlements`
- Authentication mode:
  - Caller-managed provider configuration
- Account-level vs workspace-level:
  - One workspace per module invocation (`workspace_id`)

## Constraints

- Naming conventions:
  - Stable `for_each` keys from caller input keys
  - Reserved key prefixes in output maps (`user:`, `group:`, future `sp:`)
- Backwards compatibility:
  - Additive support for future service principal scope through reserved key schema
- Security/compliance requirements:
  - Hard-fail when enabled and referenced user-group keys are missing
  - Hard-fail when enabled and `allow_empty_groups = false` with empty groups
  - Hard-fail when enabled and `workspace_id` is empty

## Validation

- `terraform fmt -recursive`
- `terraform validate`
