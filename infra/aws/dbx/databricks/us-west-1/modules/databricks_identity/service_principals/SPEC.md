# Module Spec

## Summary

- **Module name**: `databricks_identity/service_principals`
- **One-liner**: Manage new Databricks service principals with mixed account-level and workspace-level creation plus optional workspace assignment and workspace entitlements.

## Scope

- In scope:
  - One `databricks_service_principal` resource set on `databricks.mws` for `principal_scope = "account"`
  - One `databricks_service_principal` resource set on `databricks.workspace` for `principal_scope = "workspace"`
  - Optional `databricks_mws_permission_assignment` only for account-scoped principals whose `workspace_assignment.enabled = true`
  - Optional `databricks_entitlements` only for principals whose `entitlements` object is present
  - Exactly one target workspace per module invocation
- Out of scope:
  - Service principal credentials or secret resources
  - Group membership
  - Account roles
  - Unity Catalog grants
  - Warehouse permissions
  - Multi-workspace fan-out

## Interfaces

- Required inputs:
  - Provider aliases `databricks.mws` and `databricks.workspace`
  - `service_principals`
- Optional inputs:
  - `enabled`
  - `workspace_id`
- Service principal fields:
  - `service_principals[*].display_name`
  - `service_principals[*].principal_scope`
  - `service_principals[*].workspace_assignment.enabled`
  - `service_principals[*].workspace_assignment.permissions`
  - `service_principals[*].entitlements.allow_cluster_create`
  - `service_principals[*].entitlements.allow_instance_pool_create`
  - `service_principals[*].entitlements.databricks_sql_access`
  - `service_principals[*].entitlements.workspace_access`
  - `service_principals[*].entitlements.workspace_consume`
- Outputs:
  - `ids`
  - `application_ids`
  - `display_names`
  - `workspace_assignment_ids`
  - `entitlements_ids`
  - When `enabled = false`, every output is an empty map.

## Provider Context

- `databricks.mws` must target the Databricks account endpoint and is required for account-scoped service principal creation plus workspace assignment.
- `databricks.workspace` must target the single workspace represented by `workspace_id` and is required for workspace-scoped service principal creation plus all workspace entitlements.
- The caller must wire both aliases explicitly because aliased providers do not flow into child modules automatically.

## Behavior / Data Flow

- When `enabled = false`, the module becomes a no-op and all resource `for_each` collections collapse to empty maps.
- When `enabled = true`, the module splits `service_principals` by `principal_scope` into account-scoped and workspace-scoped collections.
- Account-scoped principals are created on `databricks.mws`.
- Workspace-scoped principals are created on `databricks.workspace`.
- Account-scoped principals may optionally receive `databricks_mws_permission_assignment` into exactly one workspace when `workspace_assignment.enabled = true`.
- Principals may optionally receive authoritative `databricks_entitlements` when the `entitlements` object is present, with omitted entitlement fields treated as effective `false`.
- Account-scoped principals may manage entitlements only after they are assigned into the target workspace.

## Constraints and Failure Modes

- Stable caller-defined map keys drive Terraform addresses and output keys.
- Supported `principal_scope` values are only `account` and `workspace`.
- Supported workspace assignment permission values are only `ADMIN` and `USER`.
- `workspace_assignment.permissions` must be non-empty when `workspace_assignment.enabled = true`.
- `workspace_consume` must not be `true` at the same time as `workspace_access` or `databricks_sql_access`.
- Workspace-scoped principals must not request workspace assignment.
- Account-scoped principals must not request entitlements unless workspace assignment is enabled.
- Workspace assignment requires a usable `workspace_id`.
- Due to current Databricks provider argument conflicts, `workspace_consume` is sent only when its effective value is `true`; clearing a previously granted `workspace_consume` entitlement relies on provider handling of omitted values.
- Runtime failures may still occur when:
  - the caller lacks sufficient account-level privileges on `databricks.mws`
  - the caller lacks sufficient workspace-level privileges on `databricks.workspace`
  - `display_name` collides with an existing service principal
  - `workspace_id` and `databricks.workspace` point at different workspaces

## Validation

- Required failure cases:
  - Invalid `principal_scope`
  - Invalid workspace assignment permission values
  - Empty workspace assignment permissions when assignment is enabled
  - Conflicting `workspace_consume`
  - Workspace assignment requested for workspace-scoped principals
  - Account-scoped entitlements requested without workspace assignment
  - Workspace assignment requested without a usable `workspace_id`
- Verification should include `terraform fmt`, an isolated harness `terraform validate`, root `terraform validate`, and a scenario-based root `terraform plan`.
- Direct standalone `terraform validate` in this child module is not a reliable verification step once aliased-provider resources exist, because Terraform reports missing provider configurations without a caller context.
