# Service Principals Design

Date: 2026-03-13

## Summary

Add a new mixed-scope Databricks identity module at `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals` plus a root caller at `infra/aws/dbx/databricks/us-west-1/service_principals.tf`.

One module instance manages a `map` of new service principals keyed by stable Terraform keys. Each entry declares its own `principal_scope`:

- `account`: create the principal at the Databricks account level, with optional assignment into exactly one workspace and optional workspace entitlements in that workspace
- `workspace`: create the principal directly in the target workspace, with optional workspace entitlements in that same workspace

This module owns only service principal creation plus optional workspace assignment and workspace entitlements. It intentionally excludes secrets, group membership, account roles, Unity Catalog grants, and other downstream access-control resources.

## Scope

In scope:

- New module: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals`
- New root caller: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Creating new Databricks service principals
- Mixed-scope service principal catalogs in one module instance
- Optional workspace assignment for account-scoped service principals
- Optional workspace entitlements for:
  - account-scoped service principals assigned to the target workspace
  - workspace-scoped service principals created directly in the target workspace
- Validation for:
  - invalid `principal_scope`
  - invalid workspace-permission values
  - invalid combinations of `workspace_consume`
  - workspace assignment requested for workspace-scoped principals
  - account-scoped entitlements requested without workspace assignment
  - workspace assignment requested without a usable `workspace_id`
- Stable outputs for created principal IDs, application IDs, display names, workspace assignment IDs, and entitlement IDs

Out of scope:

- Service principal credentials or secret resources
- Importing or adopting pre-existing service principals
- Group membership
- Account roles
- Unity Catalog grants
- Warehouse ACLs
- Multi-workspace fan-out from a single module instance

## Context

The repo already has a clear human-identity pattern:

- `ARCHITECTURE.md` describes identity as an account-plus-workspace concern
- `identify.tf` manages human users and groups through one central identity module call
- `modules/databricks_account/users_groups` explicitly excludes service principals

The repo also already anticipates CI service principals:

- `ARCHITECTURE.md` calls out dedicated UAT promotion and release service principals
- `docs/design-docs/unity-catalog.md` expects those principals to receive Unity Catalog access separately from identity creation
- `docs/plans/2026-03-06-existing-workspace-identity-unity-catalog-rollout.md` sketched a future service-principal path, but that draft was account-scoped and SQL-only

This design broadens that earlier draft into a reusable mixed-scope identity module while keeping the same security boundary:

- identity objects may be created in Terraform
- credentials stay outside Terraform
- direct Unity Catalog grants stay in the Unity Catalog modules that consume the service principal outputs

## Recommended Architecture

Use one public module with a mixed-scope input contract and internally split the implementation by scope.

### Module placement

Create the module under:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals`

This placement is intentional:

- `databricks_account/*` would be misleading because some principals are workspace-scoped
- `databricks_workspace/*` would be misleading because some principals are account-scoped and optionally assigned into a workspace
- `databricks_identity/*` matches the actual concern: Databricks identities that may touch both scopes

### Root caller

The checked-in root caller should live at:

- `infra/aws/dbx/databricks/us-west-1/service_principals.tf`

That file becomes the root identity catalog for Terraform-managed service principals in the same way `identify.tf` is the root identity catalog for Terraform-managed human users and groups.

### Provider model

The module should require both aliased Databricks providers:

- `databricks.mws` for account-scoped service principal creation
- `databricks.workspace` for workspace-scoped service principal creation and all workspace entitlements

The caller must wire both aliases explicitly because aliased providers do not flow into child modules automatically.

## Module Interface

### Provider context

- Required provider aliases:
  - `databricks.mws`
  - `databricks.workspace`
- Workspace model:
  - exactly one target workspace per module invocation
- Authentication model:
  - same root authentication pattern already used in this repo for Databricks resources

### Inputs

Required inputs:

- `service_principals` as `map(object(...))`

Each service principal object should include:

- `display_name` (`string`)
- `principal_scope` (`string`): `account` or `workspace`
- `workspace_assignment` (`optional(object)`):
  - `enabled` (`optional(bool, false)`)
  - `permissions` (`optional(set(string), ["USER"])`)
- `entitlements` (`optional(object)`):
  - `allow_cluster_create` (`optional(bool)`)
  - `allow_instance_pool_create` (`optional(bool)`)
  - `databricks_sql_access` (`optional(bool)`)
  - `workspace_access` (`optional(bool)`)
  - `workspace_consume` (`optional(bool)`)

Optional module inputs:

- `enabled` (`bool`, default `true`)
- `workspace_id` (`string`, default `""`)

`workspace_id` is optional at the module boundary but becomes required by validation when any account-scoped principal requests workspace assignment.

### Outputs

Expose stable maps keyed by the caller-defined service principal key:

- `ids`: SCIM IDs for created service principals
- `application_ids`: Databricks application IDs for created service principals
- `display_names`: display names for created service principals
- `workspace_assignment_ids`: assignment IDs for account-scoped principals assigned into the target workspace
- `entitlements_ids`: entitlement IDs for principals with managed entitlements

When `enabled = false`, all outputs should resolve to empty maps.

## Root Configuration Shape

The root caller should follow the existing repo identity pattern and define a stable local map keyed by Terraform-owned service principal identifiers.

Recommended shape:

```hcl
locals {
  service_principals = {
    uat_promotion = {
      display_name    = "UAT Promotion SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
      entitlements = {
        databricks_sql_access = true
      }
    }

    workspace_agent = {
      display_name    = "Workspace Agent SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_access = true
      }
    }
  }
}
```

Stable identity rules:

- the map key is the Terraform identity for the principal
- renaming a key changes Terraform addresses even if `display_name` stays the same
- downstream modules should consume outputs keyed by these same stable keys

## Behavior And Data Flow

When `enabled = false`:

- all internal locals collapse to empty maps
- no service principals, assignments, or entitlements are created
- outputs are empty maps

When `enabled = true`:

1. Split `var.service_principals` into:
   - `local.account_service_principals`
   - `local.workspace_service_principals`
2. Create account-scoped service principals with `databricks_service_principal` on `databricks.mws`
3. Create workspace-scoped service principals with `databricks_service_principal` on `databricks.workspace`
4. Build a unified local map of created principals so outputs and downstream lookups are keyed consistently
5. Materialize workspace assignments only for account-scoped principals where `workspace_assignment.enabled = true`
6. Materialize workspace entitlements only for principals where `entitlements` is provided
7. Publish stable output maps keyed by the original caller-defined service principal keys

Scope-specific behavior:

- `principal_scope = "account"`
  - create on `databricks.mws`
  - may optionally assign into the target workspace
  - may manage entitlements only when assigned into that workspace
- `principal_scope = "workspace"`
  - create directly on `databricks.workspace`
  - must not request workspace assignment
  - may manage entitlements directly in that workspace

Entitlements are authoritative when provided. If an `entitlements` object exists for a principal, the module should send all supported entitlement fields to the provider, treating omitted fields as false.

## Constraints And Failure Modes

### Contract constraints

- Supported `principal_scope` values are exactly `account` and `workspace`
- Supported workspace assignment permission values are exactly `ADMIN` and `USER`
- `workspace_consume` must not be true at the same time as `workspace_access` or `databricks_sql_access`
- Workspace-scoped principals must not request workspace assignment
- Account-scoped principals must not request entitlements unless workspace assignment is enabled
- Account-scoped principals that request workspace assignment require a non-empty `workspace_id`

### Operational constraints

- One workspace only per module invocation
- The caller must ensure `databricks.workspace` points at the same workspace represented by `workspace_id` when account-scoped assignment plus entitlements are used
- This first version creates new principals only; it does not adopt pre-existing service principals
- Credentials remain outside Terraform and are not exposed by this module

### Failure modes

Validation or precondition failures should clearly surface:

- invalid scope values
- invalid permission values
- conflicting `workspace_consume`
- workspace assignment requested for workspace-scoped principals
- account-scoped entitlements requested without workspace assignment
- account-scoped assignment requested with empty `workspace_id`

Provider or runtime failures may still occur when:

- the caller lacks account-level or workspace-level privileges
- `display_name` collides with an existing principal
- the workspace provider does not point to the intended workspace

## Integration Boundaries

This module should remain intentionally narrow.

It should not manage:

- group membership for service principals
- account roles for service principals
- Unity Catalog privileges
- SQL warehouse permissions
- secret issuance or rotation

If CI principals need direct Unity Catalog grants, those grants should be implemented in the Unity Catalog modules that already own the relevant catalogs, schemas, or volumes. Those modules should consume this module’s outputs, typically the stable `application_ids` map.

## Validation

Module-local verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals fmt -recursive`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals validate`

Root verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`

Negative-path checks to cover during planning and implementation:

- workspace-scoped principal with workspace assignment enabled
- account-scoped principal with entitlements but no workspace assignment
- invalid workspace assignment permission value
- conflicting `workspace_consume`
- non-empty assignment request with empty `workspace_id`

## Design Outcome

This design gives the repo one reusable service-principal identity module that:

- matches the existing map-driven identity style
- supports both account-scoped and workspace-scoped principals in one module instance
- keeps credentials and direct data-plane grants out of the identity layer
- keeps the first implementation narrow enough to plan and deliver incrementally
