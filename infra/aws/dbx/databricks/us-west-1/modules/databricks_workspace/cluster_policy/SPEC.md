# Module Spec

## Summary

- **Module name**: `databricks_workspace/cluster_policy`
- **One-liner**: Manage workspace-scoped Databricks cluster policies and their Terraform-owned `CAN_USE` grants.

## Scope

- In scope:
  - Creating Databricks cluster policies from caller-supplied policy JSON
  - Managing workspace-level `CAN_USE` permissions for those policies
  - Failing fast on invalid caller input for JSON shape, principal types, empty ACLs, and duplicate grant tuples
- Out of scope:
  - Embedding built-in DLT or other policy templates inside the module
  - Creating users, groups, or service principals
  - Account-level Databricks resources
  - Unity Catalog resources or permissions
  - Multi-workspace fan-out from one module invocation

## Current Stack Usage

- `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf` is the root caller and policy catalog for this module.
- The first checked-in policy key is `bundle_dlt_job`, which grants `CAN_USE` to the existing Databricks workspace group whose display name is `Platform Admins`.
- That group is provisioned through `infra/aws/dbx/databricks/us-west-1/identify.tf` via `module.users_groups`, so the root caller must depend on that module to avoid policy-permission races.
- The same caller contract is future-safe for workspace service principals, but those principals must already exist before this module grants access to them.

## Interfaces

- Required inputs:
  - `cluster_policies` (`map(object)`): caller-supplied policy catalog keyed by stable Terraform identifiers. Each value contains:
    - `name` (`string`): Databricks display name for the policy
    - `definition` (`string`): JSON policy definition passed through to `databricks_cluster_policy`
    - `description` (`optional(string)`): operator-facing policy description, also sent to the provider resource
    - `permissions` (`list(object)`): authoritative ACL entries for the policy, where each entry contains:
      - `principal_type` (`string`): one of `group`, `user`, or `service_principal`
      - `principal_name` (`string`): exact Databricks identifier for that principal type
      - `permission_level` (`optional(string, "CAN_USE")`): currently constrained to `CAN_USE`
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module becomes a no-op and all resources collapse to empty collections.
- Outputs:
  - `policy_ids`: map of stable policy keys to Databricks cluster policy IDs

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - Whatever workspace-scoped authentication the root module is already using; in this repo that is the `DATABRICKS_AUTH_TYPE=oauth-m2m` workflow for validation and plan runs.
- Account-level vs workspace-level:
  - Workspace-level only. This module must not use account-scoped provider aliases or Unity Catalog-scoped aliases.

## Behavior / Data Flow

- When `enabled = false`, the module creates no resources and `policy_ids` resolves to an empty map.
- When `enabled = true`:
  1. The module iterates over stable `cluster_policies` keys.
  2. It creates one `databricks_cluster_policy` resource per key from caller-owned JSON.
  3. It normalizes each policy's permission tuples for duplicate detection.
  4. It creates one authoritative `databricks_permissions` resource per policy so Terraform owns the full ACL for that managed policy.
  5. It translates generic principal types into provider-specific `access_control` fields:
     - `group` -> `group_name`
     - `user` -> `user_name`
     - `service_principal` -> `service_principal_name`
  6. It publishes the created policy IDs keyed by the same stable caller keys.

## Constraints and Failure Modes

- Stable caller keys are the Terraform identity for managed policies. Renaming a key changes resource addresses even if the Databricks display name stays the same.
- Every managed policy must declare at least one permission entry. Empty `permissions` lists are invalid.
- `definition` must be valid JSON. Terraform input validation rejects syntactically invalid JSON, while malformed Databricks policy structure may still fail in provider plan/apply behavior.
- Supported principal types are exactly `group`, `user`, and `service_principal`.
- Supported permission levels are constrained to `CAN_USE` in this rollout.
- Duplicate tuples of `policy_key`, `principal_type`, `principal_name`, and `permission_level` are invalid and must fail clearly rather than silently deduplicating.
- The module does not discover principals. Any referenced group, user, or service principal must already exist in the target workspace before plan/apply.
- `principal_name` semantics are Databricks-native, not Terraform-key based:
  - group: workspace group display name
  - user: Databricks `user_name`, typically login email
  - service principal: Databricks application ID

## Validation

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy validate`
- Root verification from `infra/aws/dbx/databricks/us-west-1`:
  - `terraform validate`
  - scenario 1 `terraform plan`
  - negative-path checks for unsupported `principal_type`, empty `permissions`, duplicate permission tuples, and malformed Databricks policy structure
