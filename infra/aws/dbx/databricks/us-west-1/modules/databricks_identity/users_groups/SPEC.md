# Module Spec

## Summary

- **Module name**: `databricks_account/users_groups`
- **One-liner**: Manage Databricks account groups plus memberships, roles, workspace assignments, and workspace entitlements for existing account users.

## Scope

- In scope:
  - Lookup-only existing account users via `data.databricks_user`
  - Managed account-level `databricks_group` resources
  - User-to-group membership management for looked-up users and managed groups
  - Account role attachments for looked-up users and managed groups
  - Workspace permission assignments for looked-up users and managed groups
  - Workspace entitlements for looked-up users and managed groups (authoritative when provided)
- Out of scope:
  - Creating, deleting, or SCIM-provisioning Databricks users
  - Managing membership in `okta-databricks-users`
  - Nested groups and group-to-group memberships
  - Service principals
  - Unity Catalog grants and other workspace objects outside `databricks_entitlements`
  - Multi-workspace fan-out in a single module instance

## Current Stack Usage

- `infra/aws/dbx/databricks/us-west-1/identify.tf` defines the current caller contract for this module.
- Okta SCIM provisions the human user into Databricks before Terraform runs.
- Approved users are then added to `okta-databricks-users` at the Databricks account and workspace levels.
- `local.identity_users` represents those already provisioned users for lookup and additional assignment management.
- `local.identity_groups` represents Terraform-managed Databricks account groups that this module creates and configures.
- This module layers on additional Databricks group membership plus any configured account roles, workspace permission assignments, and workspace entitlements for those users and groups.
- In the checked-in `infra/aws/dbx/databricks/us-west-1/identify.tf`, `local.identity_users` currently includes the same admin user that `module.user_assignment` in `infra/aws/dbx/databricks/us-west-1/main.tf` grants baseline workspace access. In that checked-in configuration, `module.user_assignment` preserves bootstrap admin workspace access during rollout and this module also manages any additional group-driven workspace access for that user.

## Interfaces

- Required inputs:
  - Provider aliases: `databricks.mws` and `databricks.workspace`
- Conditionally required inputs:
  - `workspace_id` when `enabled = true` (the input defaults to `""`, but `output.user_ids` enforces a non-empty value for enabled module instances)
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module becomes a no-op and all resource/data `for_each` inputs collapse to empty maps.
  - `prevent_destroy` (`bool`, default `false`): switches group creation between normal `databricks_group.groups` and lifecycle-protected `databricks_group.groups_protected`.
  - `allow_empty_groups` (`bool`, default `true`): only affects the enabled-state precondition on `output.user_ids`.
  - `users` (`map(object)`, default `{}`): existing account users keyed by stable caller-defined keys; each value contains `user_name` plus optional `groups`, `roles`, `workspace_permissions`, and `entitlements`.
  - `groups` (`map(object)`, default `{}`): managed account groups keyed by stable caller-defined keys; each value contains `display_name` plus optional `roles`, `workspace_permissions`, and `entitlements`.
- Outputs:
  - `user_ids`: map of user keys to looked-up Databricks user IDs.
  - `group_ids`: map of group keys to created Databricks group IDs.
  - `membership_ids`: map of `user:<user_key>:<group_key>` membership keys to Databricks group membership IDs.
  - `membership_keys`: set of materialized membership keys in `user:<user_key>:<group_key>` format.
  - `user_role_ids`: map of `<user_key>:<role>` keys to Databricks user role IDs.
  - `group_role_ids`: map of `<group_key>:<role>` keys to Databricks group role IDs.
  - `workspace_assignment_ids`: merged map of workspace assignment IDs keyed by `user:<user_key>` or `group:<group_key>`.
  - `entitlements_ids`: merged map of entitlement IDs keyed by `user:<user_key>` or `group:<group_key>`.

## Provider Context

- Provider(s):
  - `databricks.mws` must target the Databricks account endpoint. The module uses it for `data.databricks_user`, `databricks_group`, `databricks_group_member`, `databricks_user_role`, `databricks_group_role`, and `databricks_mws_permission_assignment`.
  - `databricks.workspace` must target the same workspace identified by `workspace_id`. The module uses it only for `databricks_entitlements`.
- Caller contract:
  - Aliased providers are not inherited automatically by child modules, so callers must wire both aliases explicitly.
  - In the checked-in root module, `databricks.mws` and `databricks.created_workspace` are passed into this module.
- Workspace scope:
  - One workspace per module invocation. The module does not discover or fan out across multiple workspaces.

## Behavior / Data Flow

- When `enabled = false`, `local.enabled_users` and `local.enabled_groups` are empty, so all user lookups and managed resources resolve to empty `for_each` collections and the outputs evaluate to empty maps or sets.
- When `enabled = true`:
  1. The module derives `referenced_group_keys` from `var.users[*].groups` and computes `invalid_group_references` against `keys(var.groups)`.
  2. It looks up each requested user in `data.databricks_user.users` by `user_name`.
  3. It creates each managed group in either `databricks_group.groups` or `databricks_group.groups_protected`, depending on `prevent_destroy`.
  4. It builds `local.user_id_map` from looked-up users and `local.group_id_map` by merging the active group resource map.
  5. It materializes `databricks_group_member.memberships` only for user/group pairs whose group key exists in `local.enabled_groups`.
  6. It materializes `databricks_user_role.user_roles` and `databricks_group_role.group_roles` from the optional `roles` sets.
  7. It materializes `databricks_mws_permission_assignment` resources only for users or groups with non-empty `workspace_permissions`.
  8. It materializes `databricks_entitlements` resources only for users or groups with non-null `entitlements`.
  9. It publishes stable output maps keyed by caller-defined user/group keys, with `user:` and `group:` prefixes on merged workspace-assignment and entitlement outputs.
- In the checked-in root stack, `identify.tf` passes `local.identity_users`, `local.identity_groups`, and `local.workspace_id`, so the current configuration exercises user lookup, group creation, membership assignment, group roles, workspace permission assignments, and entitlements against a single account/workspace pair.

## Constraints and Failure Modes

- Stable caller keys drive every `for_each` address and every output map key. Renaming a `users` or `groups` key changes Terraform instance addresses and output keys.
- Variable validations in `variables.tf`:
  - `users[*].workspace_permissions` and `groups[*].workspace_permissions` may only contain `ADMIN` or `USER`.
  - `users[*].entitlements.workspace_consume` and `groups[*].entitlements.workspace_consume` cannot be `true` at the same time as `workspace_access` or `databricks_sql_access`.
- Output preconditions in `outputs.tf` on `output.user_ids`:
  - Hard-fail when `enabled = true` and `workspace_id` is empty.
  - Hard-fail when `enabled = true`, `allow_empty_groups = false`, and `groups` is empty.
  - Hard-fail when `enabled = true` and any key referenced from `users[*].groups` is missing from `groups`; the error message lists the missing keys.
- Runtime and provider failure modes:
  - `data.databricks_user.users` fails if any `user_name` does not already exist at the Databricks account level.
  - `databricks.workspace` must point at the same workspace referenced by `workspace_id`; if they diverge, entitlement operations are mis-targeted or fail.
  - `prevent_destroy = true` adds lifecycle protection to managed groups, so deleting or replacing those groups requires an explicit operator change.
- Missing group references are intentionally filtered out of `local.memberships`; the hard failure is still enforced later by the `output.user_ids` precondition.

## Validation

- This spec is derived from the checked-in module implementation in `main.tf`, `variables.tf`, and `outputs.tf`, with current-stack usage taken from the root `identify.tf`, root `main.tf`, and `ARCHITECTURE.md`.
- Terraform enforcement is split across variable validations in `variables.tf`, output preconditions in `outputs.tf`, and provider/data-source failures at plan or apply time.
- Caller verification for this module should happen from a root module that wires both aliased providers; `terraform validate` covers schema and variable validation, while `terraform plan` can surface user lookup failures and output precondition failures. A `databricks.workspace` / `workspace_id` mismatch is not guaranteed to be detected at plan time and may instead mis-target or fail during entitlement operations.
