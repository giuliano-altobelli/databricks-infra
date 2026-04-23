# SCIM Gate Group Validation Design

## Status

- Approved on April 23, 2026.

## Context

`infra/aws/dbx/databricks/us-west-1/identify.tf` declares existing users and requested Databricks group assignments.  
`modules/databricks_identity/users_groups` currently confirms that each declared `user_name` exists in Databricks account identity (`data.databricks_user`) and then applies downstream management (group memberships, roles, workspace assignments, entitlements).

This does not enforce workspace approval from the SCIM gate group (for example `okta-databricks-users`) that represents "human is approved for this workspace."

## Goal

Gate user management in `modules/databricks_identity/users_groups` on membership in a caller-specified Databricks workspace group, with:

- per-workspace opt-in behavior,
- plan-time failure before downstream identity actions,
- batched and actionable error output listing all violating users.

## Non-Goals

- Managing membership in the SCIM gate group.
- Creating the gate group.
- Adding a custom fallback when the gate group lookup fails (provider error is acceptable).
- Changing existing behavior when gate validation is not configured.

## Interface Changes

Add one optional input to `modules/databricks_identity/users_groups`:

- `scim_gate_group_display_name` (`string`, default `""`)

Behavior:

- Gate validation is active only when `enabled = true` and `trimspace(scim_gate_group_display_name) != ""`.
- Empty value keeps current behavior unchanged.

## Design

### 1) Gate activation

Introduce:

- `local.scim_gate_enabled = var.enabled && trimspace(var.scim_gate_group_display_name) != ""`

### 2) Gate group lookup

When `local.scim_gate_enabled` is true, resolve the workspace-level group through the workspace provider:

- `data.databricks_group.scim_gate` with `display_name = var.scim_gate_group_display_name`
- provider: `databricks.workspace`

### 3) Membership normalization and diff

Normalize usernames for comparison with `lower(trimspace(...))`:

- Requested users: `local.enabled_users[*].user_name`
- Gate members: usernames derived from `data.databricks_group.scim_gate` membership payload

Compute a deterministic sorted list of violations formatted as:

- `"<user_key> (<user_name>)"`

Stored as:

- `local.scim_gate_missing_users`

### 4) Plan-time enforcement

Add one precondition alongside existing output preconditions (in `outputs.tf`):

- Condition: `!local.scim_gate_enabled || length(local.scim_gate_missing_users) == 0`
- Error message includes:
  - configured gate group display name,
  - violation count,
  - full missing-user list.

This ensures `terraform plan` fails in a single batched error before downstream membership/role/workspace/entitlement changes are accepted.

## Failure Semantics

- Gate disabled: no behavior change.
- Gate enabled + all users in gate: plan proceeds normally.
- Gate enabled + one or more users missing: plan fails with batched actionable error.
- Gate enabled + gate group not found: provider data lookup fails (accepted by design).

## Validation Strategy

From `infra/aws/dbx/databricks/us-west-1`:

1. `terraform fmt` on module files changed by the implementation.
2. `terraform validate` for syntax/type/precondition checks.
3. `terraform plan -var-file=terraform.tfvars` with required auth wrapper:
   - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars`

Scenarios to verify:

1. Gate not configured (`scim_gate_group_display_name = ""`) -> unchanged behavior.
2. Gate configured and all requested users are gate members -> plan succeeds.
3. Gate configured and at least one requested user is outside gate -> plan fails with batched message.
