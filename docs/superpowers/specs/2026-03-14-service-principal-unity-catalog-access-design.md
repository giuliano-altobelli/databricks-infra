# Service Principal Unity Catalog Access Design

Date: 2026-03-14

## Summary

Add root-level Unity Catalog access metadata to `infra/aws/dbx/databricks/us-west-1/service_principals.tf` so each Terraform-managed service principal can optionally declare:

- a Unity Catalog access level: `reader` or `writer`
- a target catalog selector: `"all"` governed catalogs or an explicit list of governed catalog keys

The actual Unity Catalog grants remain owned by the governed catalog and schema entrypoints:

- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/schema_config.tf`

This keeps `modules/databricks_identity/service_principals` focused on identity creation, workspace assignment, and entitlements, while the Unity Catalog root configuration derives grants from approved service-principal metadata.

This design intentionally targets future full-catalog service principals. It does not replace the architecture’s future layer-scoped automation roles such as `uat_promotion` or `release`.

## Scope

In scope:

- Extend the root service-principal catalog in `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Derive catalog-level reader principals in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Derive schema-level and managed-volume-level principals in `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- Support per-service-principal catalog targeting:
  - all governed catalogs
  - explicit governed catalog keys
- Support per-service-principal access levels:
  - `reader`
  - `writer`
- Keep commented-out service principals naturally out of scope
- Preserve the existing default behavior when `local.service_principals_enabled = false`
- Add validation for invalid access levels, invalid catalog selectors, blank catalog keys, duplicate catalog keys, and references to non-governed or disabled catalog keys
- Require account-scoped service principals with Unity Catalog access to be assigned into the target workspace
- Add explicit downstream ordering so Unity Catalog grants wait for service-principal workspace assignment
- Update operator documentation in `infra/aws/dbx/databricks/us-west-1/README.md`

Out of scope:

- Changes to `modules/databricks_identity/service_principals`
- Service principal credentials or secrets
- Account-level roles or group membership
- Table, view, function, or model object grants
- Fine-grained UAT-only versus production-layer-only writer roles
- Existing non-governed catalog access
- Adoption of pre-existing service principals that were not created by this root stack

## Context

The current repository boundary is already clear:

- `service_principals.tf` creates service principals and optional workspace assignments or entitlements
- `catalogs_config.tf` derives catalog-level Unity Catalog grants
- `schema_config.tf` derives schema-level and managed-volume-level grants

That separation is important because:

- `modules/databricks_identity/service_principals/SPEC.md` explicitly excludes Unity Catalog grants
- governed catalog grants are already authoritative through the Unity Catalog modules
- service principals elsewhere in the repo are referenced by Databricks application ID, not display name

The governed Unity Catalog path currently recognizes only:

- one catalog admin principal per catalog
- zero or more catalog reader principals per catalog

Schema and managed-volume grants are then derived from that reader set. There is no current root-level path for service-principal-specific Unity Catalog access, even though `ARCHITECTURE.md` and `docs/design-docs/unity-catalog.md` both anticipate service-principal-driven governed access.

## Recommended Architecture

Keep identity creation and Unity Catalog access separate, but source the Unity Catalog intent from `service_principals.tf`.

### Root-only metadata

Each active service principal may optionally declare a `unity_catalog_access` object in `service_principals.tf`.

Recommended shape:

```hcl
locals {
  service_principals = {
    catalog_maintainer = {
      display_name    = "Catalog Maintainer SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
      entitlements = {
        databricks_sql_access = true
      }
      unity_catalog_access = {
        permission_level = "writer"
        catalogs         = "all"
      }
    }

    reporting_reader = {
      display_name    = "Reporting Reader SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_access = true
      }
      unity_catalog_access = {
        permission_level = "reader"
        catalogs         = ["salesforce_revenue", "hubspot_shared"]
      }
    }
  }
}
```

This metadata lives only in the root configuration. It is not passed through to the service-principals module.

Architecture-reserved roles such as `uat_promotion` and `release` may remain commented placeholders in this file, but this generic `reader` versus `writer` rollout should not be used for those layer-scoped automation identities until a later change adds explicit schema-layer targeting.

### Derived identity locals

Because the identity module has a strict typed input contract and should not absorb Unity Catalog concerns, `service_principals.tf` should derive two root locals:

- an identity-only map passed into `module.service_principals`
- a normalized Unity Catalog access map used only by the governed Unity Catalog root logic

That keeps the service-principals module interface unchanged and avoids coupling Unity Catalog rollout details into the identity module contract.

### Application ID as the grant principal

For service principals, the Unity Catalog principal string should be the Databricks application ID from:

- `module.service_principals.application_ids`

The design should not use display names for service-principal Unity Catalog grants. This matches the repo’s existing permission patterns for service principals in warehouse and storage examples.

## Permission Model

This change introduces a simple governed-catalog access model for service principals.

### Catalog targeting

`unity_catalog_access.catalogs` supports two modes:

- `"all"`: all enabled governed catalogs, excluding `personal`
- `["catalog_key_a", "catalog_key_b"]`: only the listed enabled governed catalog keys

The selector is resolved against the root governed catalog keys already defined in `catalogs_config.tf`, such as `salesforce_revenue` or `hubspot_shared`.

Requested catalog keys must be:

- non-empty
- unique
- present in the enabled governed catalog set
- not `personal`

If `unity_catalog_access` is present for an account-scoped service principal, that principal must also set:

- `workspace_assignment.enabled = true`

This is required because Unity Catalog grants are workspace-scoped in this stack and the principal must exist in the target workspace before grant application.

### Reader access

`permission_level = "reader"` grants the targeted service principal:

- Catalog: `USE_CATALOG`
- Schema: `USE_SCHEMA` on governed schemas in the targeted catalog
- Managed volume: `READ_VOLUME` on governed managed volumes in the targeted catalog

This matches the current root reader pattern already applied to reader groups, with the same limitation: the governed stack does not currently manage table or view `SELECT` grants.

### Writer access

`permission_level = "writer"` grants the targeted service principal:

- Catalog: `USE_CATALOG`
- Schema: `ALL_PRIVILEGES` on governed schemas in the targeted catalog
- Managed volume: `READ_VOLUME` and `WRITE_VOLUME` on governed managed volumes in the targeted catalog

`ALL_PRIVILEGES` is used at schema scope because the checked-in `unity_catalog_schemas` module currently supports only `ALL_PRIVILEGES` and `USE_SCHEMA`.

This writer model is intentionally broader than the future architecture split between:

- UAT-only promotion writers
- production-layer release writers

That finer separation remains a later additive change. This design only introduces a simple, explicit reader-versus-writer contract for future full-catalog service principals and must not be used for the architecture-defined `uat_promotion` or `release` roles in their final form.

## Root Data Flow

### `service_principals.tf`

1. Keep `local.service_principals` as the operator-authored source of truth.
2. Derive an identity-only map for `module.service_principals`.
3. Derive a normalized Unity Catalog access map keyed by the same stable service-principal keys.
4. Validate that any account-scoped principal with Unity Catalog access also has `workspace_assignment.enabled = true`.
5. When `local.service_principals_enabled = false`, collapse the Unity Catalog access derivation to an empty map so checked-in examples remain inert.

### `catalogs_config.tf`

1. Keep group-based `reader_group` behavior unchanged.
2. Derive catalog-targeted reader application IDs from the normalized service-principal Unity Catalog access map.
3. Treat both service-principal readers and service-principal writers as catalog readers for catalog scope because both need `USE_CATALOG`.
4. Merge those application IDs into the existing `catalog_reader_principals` list for each governed catalog.
5. Extend the existing `module "governed_catalogs"` dependency contract with `module.service_principals` so workspace assignment completes before Unity Catalog grants are applied for account-scoped principals.

No child module interface changes are required because `unity_catalog_catalog_creation` already accepts a flat list of principals that receive `USE_CATALOG`.

### `schema_config.tf`

1. Derive service-principal reader and writer application IDs per governed catalog.
2. Extend default schema grant generation:
   - reader principals receive `USE_SCHEMA`
   - writer principals receive `ALL_PRIVILEGES`
3. Extend default managed-volume grant generation:
   - reader principals receive `READ_VOLUME`
   - writer principals receive `READ_VOLUME` and `WRITE_VOLUME`
4. Preserve the current override semantics:
   - explicit schema `grants` still replace derived defaults
   - explicit managed-volume `grants` still replace derived defaults
5. Extend the `module "unity_catalog_schemas"` and `module "unity_catalog_volumes"` dependency contracts with `module.service_principals` for the same workspace-assignment ordering reason.

This means service-principal access participates only in the derived default path. If a catalog-specific override replaces a schema or managed-volume grant list, the operator remains responsible for including any service-principal grants that should survive that override.

## Stable Identity Rules

- The stable Terraform identity for a service principal remains its key in `local.service_principals`
- Unity Catalog access metadata is keyed by that same service-principal key
- Catalog targeting uses the existing governed catalog stable keys from `catalogs_config.tf`
- Commented-out service principals remain out of scope because commented HCL entries do not enter the evaluated locals

## Constraints And Failure Modes

### Constraints

- Supported `unity_catalog_access.permission_level` values are only `reader` and `writer`
- Supported catalog selectors are only:
  - the exact string `"all"`
  - a non-empty list of unique governed catalog keys
- `personal` is not a valid target for this change
- Unity Catalog access must remain a root concern; the service-principals child module contract should not be widened for this feature
- Service-principal grants must use application IDs, not display names
- Account-scoped service principals may declare Unity Catalog access only when `workspace_assignment.enabled = true`
- The governed catalog, schema, and managed-volume root callers must wait on `module.service_principals`, not only on `application_ids` data references, so workspace assignment is complete before grant application

### Failure modes

Validation or check failures should clearly surface when:

- a permission level is not `reader` or `writer`
- `catalogs` is neither `"all"` nor a list of non-empty strings
- a catalog key is duplicated in an explicit list
- an explicit catalog key does not resolve to an enabled governed catalog
- an explicit catalog key points at `personal`
- an account-scoped principal declares Unity Catalog access without workspace assignment

Runtime failures may still occur when:

- the referenced service principal was not created because `service_principals_enabled` was false and the root logic was not correctly gated
- the Databricks provider rejects a Unity Catalog grant even though the principal exists
- the principal exists at the account level but is not yet assigned into the workspace when Unity Catalog grants are attempted
- an explicit schema or volume override replaces derived grants and intentionally or accidentally omits a service principal that previously had access

## Validation

Verification should focus on root behavior because the child module interfaces are intentionally unchanged.

Minimum verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`

Suggested targeted scenarios:

- one service principal with `reader` access to `"all"`
- one service principal with `writer` access to one explicit governed catalog key
- one commented-out service principal with Unity Catalog metadata to confirm it remains inert
- one negative-path local edit using an invalid catalog key or invalid permission level to confirm validation fails clearly

## Implementation Notes

This feature should be implemented without changing the typed interface of `modules/databricks_identity/service_principals`.

The desired layering is:

- `service_principals.tf`: operator-authored identity and Unity Catalog intent
- `catalogs_config.tf`: catalog-level grant derivation
- `schema_config.tf`: schema and managed-volume grant derivation
- `modules/databricks_identity/service_principals`: unchanged identity lifecycle owner

Explicit root ordering is also part of the contract:

- `module.governed_catalogs`
- `module.unity_catalog_schemas`
- `module.unity_catalog_volumes`

must all extend their existing `depends_on` lists with `module.service_principals` when service-principal Unity Catalog access is in play.

That boundary plus the explicit ordering contract are the main design decisions in this change.
