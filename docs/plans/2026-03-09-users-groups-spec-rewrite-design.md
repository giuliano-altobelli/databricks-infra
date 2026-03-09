# Users Groups Spec Rewrite Design

**Date:** 2026-03-09

**Goal:** Fully rewrite `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/SPEC.md` so it reflects the current Terraform implementation and the way the root stack uses the module today.

## Context

The current module spec has drifted from the Terraform behavior in:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/identify.tf`
- `ARCHITECTURE.md`

The repo architecture is explicit that user lifecycle is managed outside Terraform through Okta SCIM, and that `identify.tf` is no longer used to create users. The module spec still describes account-level `databricks_user` management, which no longer matches the implementation.

## Source Of Truth

For this rewrite, current Terraform behavior is the source of truth.

- The module implementation defines the contract.
- `ARCHITECTURE.md` is the consistency guardrail for repo-wide identity intent.
- `identify.tf` provides the current root-module usage that the spec should describe clearly.
- The rewrite should correct the spec. It should not propose Terraform behavior changes.

## Validated Findings

### Drift Between `SPEC.md` And Terraform

1. The spec says the module manages account-level `databricks_user`, but the implementation uses `data "databricks_user"` to look up existing users by `user_name`.
2. The spec does not clearly state that groups are created by Terraform while users are lookup-only.
3. The spec does not document the actual validation and failure behavior implemented in `variables.tf` and `outputs.tf`.
4. The spec does not explain the current stack usage in `identify.tf`, where SCIM-provisioned users are passed in for additional Databricks group and entitlement management.

### Behavior Confirmed From Terraform

- `enabled` gates all user and group processing.
- Users are existing account principals looked up through the account-level provider.
- Groups are created through the account-level provider, with optional `prevent_destroy`.
- Memberships are user-to-group only.
- User and group roles are optional and account-scoped.
- Workspace permission assignments are optional and scoped to one `workspace_id`.
- Workspace entitlements are optional and managed through the workspace-level provider.
- Output maps use stable caller keys and reserved `user:` / `group:` prefixes where applicable.

## Approved Rewrite Direction

Rewrite `SPEC.md` as an implementation-derived contract with current stack usage context.

This means the new spec should:

- describe what the module actually creates, looks up, and manages
- document how `identify.tf` uses the module in this repo
- align terminology with the SCIM-first identity model in `ARCHITECTURE.md`
- capture the real validations and failure modes already implemented

This rewrite is documentation-only. No Terraform resources or behavior should change as part of this effort.

## Target Spec Structure

The rewritten `SPEC.md` should use this structure:

1. **Summary**
   - State that the module manages Databricks account groups and assignments for existing account users in one target workspace.
2. **Scope**
   - Separate lookup-only user behavior from Terraform-managed group behavior.
   - Include memberships, account roles, workspace assignments, and workspace entitlements.
3. **Current Stack Usage**
   - Explain that `identify.tf` passes SCIM-provisioned humans and additional group definitions.
   - Note that baseline user provisioning and default Okta-driven membership are outside this module.
4. **Interfaces**
   - Document provider aliases, optional inputs, and outputs with their current semantics.
5. **Behavior / Data Flow**
   - Describe the order and derivation of lookups, group creation, memberships, roles, workspace assignments, and entitlements.
6. **Constraints And Failure Modes**
   - Document both variable validations and output preconditions exactly as implemented.
7. **Out Of Scope**
   - Exclude user creation, service principals, nested groups, and multi-workspace fan-out in a single module instance.
8. **Validation**
   - Keep repo validation steps concise and aligned with the current documentation-only change.

## Required Contract Corrections

The rewritten spec must explicitly state:

- `users` are existing account-level users looked up by `user_name`
- `groups` are created and managed by the module
- memberships are limited to user-to-group relationships
- one workspace is targeted per module invocation
- `databricks.mws` handles account-scoped lookups and assignments
- `databricks.workspace` handles workspace-level entitlements
- entitlements are only managed for principals where an `entitlements` object is provided

The rewritten spec must also document these implemented constraints:

- `workspace_permissions` may only contain `ADMIN` or `USER`
- `workspace_consume` cannot be `true` when `workspace_access` or `databricks_sql_access` is `true`
- the module hard-fails when enabled and `workspace_id` is empty
- the module hard-fails when enabled and `allow_empty_groups = false` with an empty `groups` map
- the module hard-fails when a user references a missing group key

The spec should note that the last three hard-fail checks are currently enforced through output preconditions, because that is part of the implementation reality being documented.

## Non-Goals

- changing Terraform resource behavior
- expanding support to service principals
- adding nested group membership support
- adding multi-workspace fan-out to a single module instance
- changing `identify.tf` behavior

## Acceptance Criteria

The design is complete when:

1. `SPEC.md` no longer claims to manage `databricks_user` resources.
2. `SPEC.md` clearly describes the SCIM lookup model used by the module and root stack.
3. Every declared constraint in the spec can be traced to current Terraform code.
4. The spec can be read without ambiguity about account scope, workspace scope, or provider usage.
5. The rewrite remains documentation-only and does not alter Terraform behavior.
