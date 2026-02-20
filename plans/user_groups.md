# Terraform Module: `databricks_account/users_groups` (Users, Groups, Memberships, Roles, Entitlements, Workspace Assignments)

## Summary

Create a new Terraform module at `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups` (based on the repo `_module_template`) that manages:

- Account-level users and groups
- User-to-group memberships
- Account roles for users and groups
- Workspace permission assignments (account-level assignment to a workspace)
- Workspace entitlements for users and groups

Hard-fail behaviors:

- Fail if any `users[*].groups` references a missing group key in `var.groups`.
- Fail if `enabled = true` and `allow_empty_groups = false` but `groups = {}`.
- Fail if workspace-scoped features are requested without `workspace_id` (we’ll make `workspace_id` required when `enabled = true`, since workspace assignments + entitlements are included).

Decisions locked:

- `prevent_destroy` default: `false`
- Empty `groups = {}` allowed by default: `true`
- Workspace scope: exactly one workspace per module invocation
- Workspace permission assignments: support users + groups
- Entitlements mode: authoritative (module enforces provided values)
- Roles: support `account_admin` plus arbitrary role strings

## Provider Contract (Two Providers Passed by Caller)

This module does not configure `provider "databricks"` blocks. The caller supplies:

- `databricks.mws` (account-level, e.g. `accounts.cloud.databricks.com`) for users/groups/roles/mws permission assignments.
- `databricks.workspace` (workspace-level, host = the target workspace URL) for `databricks_entitlements`.

Module implementation requirements:

- `versions.tf` uses `configuration_aliases = [databricks.mws, databricks.workspace]`.
- Each resource explicitly selects the correct provider via `provider = databricks.mws` or `provider = databricks.workspace`.

README usage example will show:

- `providers = { databricks.mws = databricks.mws, databricks.workspace = databricks.created_workspace }`

## Public Interface (Variables)

Keep `enabled` from the template.

Add variables:

- `workspace_id` (string): target workspace id for workspace permission assignments; also documents which workspace the `databricks.workspace` provider should point at.
- `prevent_destroy` (bool, default `false`): applied to `databricks_user` and `databricks_group` resources.
- `allow_empty_groups` (bool, default `true`)
- `groups` (map(object({
  - `display_name` = string
  - `roles` = optional(set(string), [])
  - `workspace_permissions` = optional(set(string), [])
  - `entitlements` = optional(object({
      `allow_cluster_create` = optional(bool, false)
      `allow_instance_pool_create` = optional(bool, false)
      `databricks_sql_access` = optional(bool, false)
      `workspace_access` = optional(bool, false)
      `workspace_consume` = optional(bool, false)
    }))
})), default `{}`)
- `users` (map(object({
  - `user_name` = string
  - `display_name` = optional(string)
  - `active` = optional(bool)
  - `groups` = optional(set(string), [])
  - `roles` = optional(set(string), [])
  - `workspace_permissions` = optional(set(string), [])
  - `entitlements` = optional(object({
      `allow_cluster_create` = optional(bool, false)
      `allow_instance_pool_create` = optional(bool, false)
      `databricks_sql_access` = optional(bool, false)
      `workspace_access` = optional(bool, false)
      `workspace_consume` = optional(bool, false)
    }))
})), default `{}`)

Validation rules:

- Missing group-key check: referenced group keys in `users[*].groups` must be subset of `keys(var.groups)` (when `enabled = true`).
- Empty groups rule: enforced when `enabled = true && allow_empty_groups = false`.
- Workspace requirements: when `enabled = true`, require `workspace_id` non-empty.
- Permission value validation: validate `workspace_permissions` against the allowed values from provider docs (expected `ADMIN`/`USER`; finalize after Registry/Context7 lookup and record in `FACTS.md`).

## Resources (What Gets Created)

All resources are created with `for_each` keyed by stable keys derived from input keys, so IDs are stable.

Account-level identity (provider = `databricks.mws`):

- `databricks_user.users` for all `var.users`
- `databricks_group.groups` for all `var.groups`
- `databricks_group_member.memberships` for each `user:${user_key}:${group_key}` pair in `users[*].groups` (deduped by set semantics)
- `databricks_user_role.user_roles` for each `${user_key}:${role}`
- `databricks_group_role.group_roles` for each `${group_key}:${role}`
- `databricks_mws_permission_assignment.user_workspace_assignments` for each `${user_key}` where `users[user_key].workspace_permissions` non-empty
- `databricks_mws_permission_assignment.group_workspace_assignments` for each `${group_key}` where `groups[group_key].workspace_permissions` non-empty

Workspace-level entitlements (provider = `databricks.workspace`):

- `databricks_entitlements.user_entitlements` for each user with `entitlements` set
- `databricks_entitlements.group_entitlements` for each group with `entitlements` set

Authoritative behavior:

- If `entitlements` is provided for a principal, set all entitlement fields (using the defaults of `false` for unspecified fields in the object).

Lifecycle safety:

- `lifecycle { prevent_destroy = var.prevent_destroy }` on `databricks_user` and `databricks_group` only (not on membership/role/assignment/entitlements resources).

## Outputs

Required outputs:

- `user_ids` map(string): `{ user_key => databricks_user.users[user_key].id }`
- `group_ids` map(string): `{ group_key => databricks_group.groups[group_key].id }`

Additional outputs (requested/usable for debugging and composability):

- `membership_ids` map(string): `{ "user:${user_key}:${group_key}" => databricks_group_member.memberships[key].id }`
- `membership_keys` set(string)
- `user_role_ids` map(string): `{ "${user_key}:${role}" => databricks_user_role.user_roles[key].id }`
- `group_role_ids` map(string): `{ "${group_key}:${role}" => databricks_group_role.group_roles[key].id }`
- `workspace_assignment_ids` map(string): include both users and groups, keyed as `"user:${user_key}"` / `"group:${group_key}"` (reserve `"sp:${sp_key}"` for future service principals)
- `entitlements_ids` map(string): `"user:${user_key}"` / `"group:${group_key}"` for created entitlement resources (reserve `"sp:${sp_key}"` for future service principals)

## `FACTS.md` (Docs → Durable Facts Ledger)

During implementation, add a short fact row (with source pointer) for each of:

- `databricks_user` account-level fields used (`user_name`, `display_name`, `active`, any gotchas like `force` if we decide to use it)
- `databricks_group` required/optional args
- `databricks_group_member` required args and ID/import format
- `databricks_user_role` + `databricks_group_role` arguments (`role` values and ID format)
- `databricks_mws_permission_assignment` args, allowed `permissions` values, ID/import format, principal types
- `databricks_entitlements` requirement that it “must be used with a workspace-level provider” and its supported entitlement fields

Sources:

- Terraform Registry pages for each resource, plus Context7 `/databricks/terraform-provider-databricks` query topics used to derive each non-obvious behavior.

## README Usage Example

Include a minimal example showing:

- Passing both providers (`databricks.mws` + `databricks.workspace`)
- Defining `groups` and `users`
- Assigning memberships via `users[*].groups`
- Assigning roles via `users[*].roles` / `groups[*].roles`
- Assigning workspace permissions via `workspace_permissions = ["ADMIN"]` etc
- Defining entitlements per user/group via `entitlements = { ... }`
- Note that entitlements are applied in the single workspace whose provider config is passed as `databricks.workspace`

## Validation Checklist (Implementation Phase)

- `terraform fmt -recursive` in the module dir
- `terraform validate` (after `terraform init` in an appropriate context)

Behavior scenarios to verify:

1. Missing group key in `users[*].groups` fails at plan-time with a clear message listing missing keys.
2. `enabled = false` yields no resources and empty outputs.
3. If a user has `workspace_permissions` but `workspace_id` is missing/empty, plan fails with clear validation error.
4. Roles create expected `databricks_user_role`/`databricks_group_role` instances keyed by `${principal_key}:${role}`.
5. Entitlements resources only created when `entitlements` block is provided; values are enforced (authoritative).

## Assumptions / Constraints

- Exactly one workspace is targeted per module invocation; for multiple workspaces, instantiate this module multiple times with different `workspace_id` and `databricks.workspace` provider configs.
- No service principals in scope unless explicitly added later. Key schemas reserve the `sp:` prefix so service principals can be added as an additive change without key collisions.
