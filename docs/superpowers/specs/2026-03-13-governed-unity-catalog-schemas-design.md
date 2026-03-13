# Governed Unity Catalog Schemas Design

Date: 2026-03-13

## Summary

Add a new governed-schema entrypoint at `infra/aws/dbx/databricks/us-west-1/schema_config.tf` and a focused workspace-scoped Terraform module at `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas`.

`schema_config.tf` becomes the single source of truth for this rollout’s governed Unity Catalog layer schemas and their optional managed volumes. The new module owns only schema creation and authoritative schema grants. Root orchestration in `schema_config.tf` reuses the existing `unity_catalog_volumes` module for optional managed volumes, and the checked-in governed entrypoint in `volume_config.tf` is removed.

This change is governed-catalog-only. It does not create `personal.<user_key>` schemas and does not add workspace-level permissions.

## Scope

In scope:

- New root entrypoint: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- New workspace-scoped module: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas`
- Governed schema creation for enabled governed catalogs already derived in `catalogs_config.tf`
- Standard governed schema set: `raw`, `base`, `staging`, `final`, and `uat`
- Authoritative schema grants for module-managed schemas
- Optional managed-volume declarations under governed schemas through `schema_config.tf`
- Root orchestration that reuses the existing `unity_catalog_volumes` module for those optional managed volumes
- Validation for duplicate schema identities, duplicate grant tuples, invalid privileges, invalid catalog references, and invalid managed-volume declarations
- README and operator-doc updates so governed schema and managed-volume configuration point to `schema_config.tf`
- Intentional removal of the checked-in root entrypoint in `volume_config.tf`

Out of scope:

- `personal.<user_key>` schemas
- Account-level Databricks resources or `databricks.mws`
- Workspace-level assignments, entitlements, or compute permissions
- Table, view, function, model, or row-level grants
- External volumes
- Storage credentials, external locations, or catalog creation
- Replacing the underlying `unity_catalog_volumes` module
- Preserving a checked-in standalone root caller for external or non-governed volumes

## Context

The repository already has a clean pattern for workspace-scoped Unity Catalog modules:

- `unity_catalog_catalog_creation` for catalog bootstrap
- `unity_catalog_storage_locations` for storage credentials and external locations
- `unity_catalog_volumes` for managed and external volumes

What is missing is the schema layer between governed catalogs and volumes. `ARCHITECTURE.md` expects governed domain catalogs to expose `raw`, `base`, `staging`, `final`, and `uat`, with different writer roles for `uat` versus production-layer schemas.

The approved boundary for this change is:

- `catalogs_config.tf` remains the governed catalog source
- `schema_config.tf` becomes the governed schema and optional managed-volume source
- the new `unity_catalog_schemas` module stays focused on schemas and schema grants
- optional managed volumes remain implemented by the existing `unity_catalog_volumes` module, but its root invocation moves under `schema_config.tf`

This keeps one config surface for governed Unity Catalog policy without broadening the new module beyond schema concerns.

For this rollout, the schema policy contract is intentionally limited to catalog admins and catalog readers on fresh Terraform-managed governed schemas. `uat_writer_principals` and `release_writer_principals` may appear only as commented placeholders in examples for future work; they are not active inputs, are not validated, and do not change grants in this change. CI writer enablement is explicitly deferred to a follow-up change before these schemas are treated as the full end-state access model from `ARCHITECTURE.md`.

## Recommended Architecture

Use one new root entrypoint plus one focused schema module.

### Root entrypoint

`schema_config.tf` should:

- derive its target catalog set from `local.catalogs` in `catalogs_config.tf`
- filter to governed catalogs only
- expand each governed catalog into five schema records: `raw`, `base`, `staging`, `final`, and `uat`
- derive schema grants from the catalog-level admin and reader principals
- collect optional managed-volume declarations under those schemas
- flatten managed-volume declarations into the existing `unity_catalog_volumes` input shape
- invoke the new schema module and the existing volume module with explicit ordering
- source catalog names from `module.governed_catalogs` outputs and keep an explicit dependency on `module.governed_catalogs`

`schema_config.tf` is the single checked-in configuration surface for this rollout’s governed schemas and optional governed managed volumes. The checked-in governed `volume_config.tf` root caller should be removed to avoid split policy ownership.

This is an intentional root-level consolidation change:

- the `unity_catalog_volumes` module remains in the repo and remains reusable
- the checked-in `volume_config.tf` root caller is deleted rather than merged into `schema_config.tf`
- this design does not introduce a second checked-in root entrypoint for external or non-governed volumes
- if operators need external or non-governed volume orchestration later, that should be added in a separate root-caller change instead of preserving two parallel checked-in config surfaces now

Because the checked-in `volume_config.tf` currently defaults to an empty example map, deleting it is a repo-surface consolidation. Any locally customized uses of that file would need manual migration to `schema_config.tf` for governed managed volumes or to a future dedicated root caller for non-governed or external volumes.

### Focused schema module

`modules/databricks_workspace/unity_catalog_schemas` should own only:

- one `databricks_schema` resource per schema entry
- one authoritative `databricks_grants` resource per schema entry when grants are declared

The module must not create:

- catalogs
- volumes
- storage credentials
- external locations
- account-level identities or resources

That boundary keeps the module easy to test and makes the root caller responsible for orchestration between catalogs, schemas, and optional volumes.

## Root Configuration Shape

`schema_config.tf` should define a local configuration map keyed by governed catalog key. The stable key space must align with the keys already present in `local.catalogs`.

Recommended shape:

```hcl
locals {
  governed_schema_config = {
    salesforce_revenue = {
      managed_volumes = {
        final = {
          model_artifacts = {
            name = "model_artifacts"
          }
        }
        uat = {
          candidate_assets = {
            name = "candidate_assets"
          }
        }
      }

      # Placeholder only for future schema-writer rollout:
      # uat_writer_principals     = ["00000000-0000-0000-0000-000000000000"]
      # release_writer_principals = ["11111111-1111-1111-1111-111111111111"]
    }
  }
}
```

Required behavior:

- only catalog keys already present in governed `local.catalogs` are valid
- omitted catalog keys still receive the standard schema set with default schema grants and no managed volumes
- managed volumes may only be declared under `raw`, `base`, `staging`, `final`, or `uat`
- commented writer-principal placeholders are documentation only in this rollout and are not parsed by Terraform

The root caller should derive a normalized catalog-policy map so callers can override only what differs per catalog.

Stable Terraform identity rules:

- schema records use the canonical key format `<catalog_key>:<schema_name>`
- managed-volume records use the canonical key format `<catalog_key>:<schema_name>:<volume_key>`
- `<catalog_key>` is the stable key already used in `local.catalogs`
- `<schema_name>` is one of `raw`, `base`, `staging`, `final`, or `uat`
- `<volume_key>` is the stable caller-defined key under `managed_volumes.<schema_name>`

These canonical keys are the long-term Terraform identity and output key contract for this design. Renaming one of those keys changes Terraform addresses even if the Databricks display name does not change.

## Schema Module Interface

### Provider context

- Provider: `databricks`
- Caller wiring: `providers = { databricks = databricks.created_workspace }`
- Provider scope: workspace-level only

The module must not use `databricks.mws`.

### Inputs

Required inputs:

- `schemas` as `map(object(...))`

Each schema object should include:

- `catalog_name` (`string`)
- `schema_name` (`string`)
- `comment` (`optional(string)`)
- `grants` (`optional(list(object)), []`) where each grant contains:
  - `principal` (`string`)
  - `privileges` (`list(string)`)

Optional module inputs:

- `enabled` (`bool`, default `true`)

### Outputs

Expose a `schemas` output map keyed by stable caller key. Each value should include at least:

- `catalog_name`
- `schema_name`
- `full_name`

When `enabled = false`, the module creates no resources and returns an empty output map.

## Grant Model

Schema grants are authoritative for every module-managed schema.

Default schema grant rules:

- catalog admin principal receives `ALL_PRIVILEGES` on every managed schema
- catalog reader principals receive `USE_SCHEMA` on every managed schema

These rules intentionally manage schema permissions only. They do not attempt to manage table or view data privileges in this change.

Grant rendering should follow the repo’s existing pattern:

- flatten `(schema_key, principal, privilege)` tuples
- reject duplicate tuples rather than silently deduplicating
- regroup privileges by principal before rendering `databricks_grants`

Supported schema privileges for this rollout are intentionally limited to:

- `ALL_PRIVILEGES`
- `USE_SCHEMA`

This narrower contract is sufficient for the approved root-derived schema grants and avoids widening the module interface before there is a concrete caller need. Expanding schema privilege support is a separate additive change.

Because these schemas are created fresh in this rollout, there are no pre-existing writer grants that need to be preserved on the managed schema set. The authoritative grant contract therefore applies only to the principals explicitly in scope here: catalog admins and catalog readers.

## Optional Managed Volumes

Optional managed volumes are declared only in `schema_config.tf`, not in a separate governed `volume_config.tf` entrypoint.

Each managed volume declaration should flatten into the input contract already used by `unity_catalog_volumes`:

- `name`
- `catalog_name`
- `schema_name`
- `volume_type = "MANAGED"`
- `comment` (`optional`)
- `owner` (`optional`)
- `grants` (`optional`)

Default volume grant rules:

- catalog admin principal receives `ALL_PRIVILEGES`
- catalog reader principals receive `READ_VOLUME`

Override rule:

- when a managed volume omits `grants`, root derives the default grant set for that schema layer
- when a managed volume declares `grants`, that list fully replaces the derived default grant set for that volume
- explicit `grants = []` is invalid; callers must omit `grants` to inherit defaults or provide a non-empty replacement list

Replacement semantics are preferred here because the downstream volume module manages grants authoritatively and should receive one unambiguous final grant set.

## Data Flow

1. `catalogs_config.tf` derives `local.catalogs`.
2. `schema_config.tf` filters `local.catalogs` to governed catalogs only.
3. Root reads the authoritative catalog names from `module.governed_catalogs[<catalog_key>].catalog_name`.
4. Root expands each governed catalog into `raw`, `base`, `staging`, `final`, and `uat`.
5. Root derives schema grants from:
   - `catalog_admin_principal`
   - `catalog_reader_principals`
6. Root passes the flattened schema map into `module.unity_catalog_schemas`.
7. Root flattens optional managed-volume declarations into the input map expected by `module.unity_catalog_volumes`.
8. Root derives default volume grants unless an explicit volume `grants` list is present.
9. `module.unity_catalog_volumes` runs only after schemas are created.

The intended dependency contract in `schema_config.tf` is:

- keep the baseline `depends_on = [module.unity_catalog_metastore_assignment, module.users_groups]`
- make schema creation depend explicitly on `module.governed_catalogs`
- add explicit ordering so volume creation depends on schema creation when Terraform cannot infer it from values alone

## Error Handling And Validation

The design should fail before apply drift rather than relying on Databricks runtime errors.

Root-level validation in `schema_config.tf` should reject:

- unknown catalog keys in `governed_schema_config`
- non-governed catalog references
- managed-volume declarations under unsupported schema names
- duplicate fully qualified managed-volume identities after flattening
- invalid grant shapes passed to volume overrides, including explicit empty override lists

Module-level validation in `unity_catalog_schemas` should reject:

- blank `catalog_name`
- blank `schema_name`
- blank grant principals
- empty privilege lists
- invalid privilege names
- duplicate fully qualified schema identities across stable keys
- duplicate schema grant tuples

Expected runtime failure modes that remain outside static validation:

- target catalog does not exist
- workspace is not correctly assigned to the metastore
- Databricks rejects a privilege that differs from the provider’s documented schema privilege contract
- a caller expects out-of-band schema or volume grants to persist after authoritative apply

## Testing And Verification

Module verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate`

Repo formatting:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`

Root verification from `infra/aws/dbx/databricks/us-west-1`:

- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`

Negative-path checks should cover:

- duplicate schema identities across stable keys
- duplicate schema grant tuples
- invalid schema privilege names
- managed volumes under unsupported schema names
- duplicate fully qualified managed-volume identities
- invalid volume-grant override privileges

Documentation updates should:

- add schema guidance to `infra/aws/dbx/databricks/us-west-1/README.md`
- point governed managed-volume configuration to `schema_config.tf`
- remove governed operator guidance that references `volume_config.tf` as the checked-in config entrypoint
- add the standard `SPEC.md` and `README.md` for `modules/databricks_workspace/unity_catalog_schemas`

To exercise the real success path, verification must include a scratch copy or temporary local edit that enables at least one non-`personal` governed catalog in `catalogs_config.tf` and one managed-volume example in `schema_config.tf`. The checked-in default `personal`-only baseline is not sufficient to validate this rollout by itself.
