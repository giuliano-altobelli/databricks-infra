# Unity Catalog Volumes Design

Date: 2026-03-12

## Summary

Create a new workspace-scoped Terraform module for Databricks Unity Catalog volumes that supports both managed and external volume types through a single `volumes` input map.

The module will manage only volume resources and authoritative volume grants. It will not create catalogs, schemas, external locations, or account-level resources.

## Scope

In scope:

- New module: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes`
- Workspace-level Databricks provider usage only
- Managed creation of Unity Catalog `MANAGED` and `EXTERNAL` volumes
- Authoritative `databricks_grants` management for each module-managed volume when grants are declared
- Input validation for volume type, required fields, privilege names, and duplicate grant tuples
- Standard module docs and outputs

Out of scope:

- Account-level Databricks resources or `databricks.mws`
- Creating or managing catalogs or schemas
- Creating or managing external locations
- Creating or managing storage credentials
- Workspace bindings in this module
- AWS resources or path bootstrap outside Databricks

## Context

This repository already has a workspace-scoped Unity Catalog storage locations module at `modules/databricks_workspace/unity_catalog_storage_locations`. The new volume module should follow the same general module conventions:

- caller wires the workspace-scoped `databricks.created_workspace` provider alias
- module keys are stable Terraform identities
- grants are authoritative when managed
- invalid inputs should fail early with explicit validation or preconditions

The user explicitly scoped this work to Unity Catalog and workspace level only.

## Recommended Architecture

Use one focused module with one clear responsibility:

- inputs describe the desired set of Unity Catalog volumes
- the module creates one `databricks_volume` per entry
- the module optionally creates one authoritative `databricks_grants` resource per volume

The module should reference prerequisite objects by name instead of creating them. Each volume object names its target catalog and schema directly. External volumes also pass the full `storage_location` URI directly.

This keeps the boundary aligned with the existing storage-location module and avoids coupling volume lifecycle to storage bootstrap concerns.

Root integration contract:

- if catalogs or schemas are created in the same root stack, callers should pass those names from resource or module outputs instead of duplicating literal strings
- if Terraform still cannot infer a required prerequisite edge, the root module should add explicit `depends_on` to the volume module invocation
- for `EXTERNAL` volumes, `storage_location` must point to a directory inside an already-created external location with the necessary Databricks-side authorization already in place
- if the same root stack also manages the external location or its grants, the root caller is responsible for enforcing apply ordering with references and, when needed, explicit `depends_on`

## Module Interface

### Provider Context

- Provider: `databricks`
- Caller wiring: `providers = { databricks = databricks.created_workspace }`
- Provider scope: workspace-level only

The module must not reference `databricks.mws` or any account-scoped resource.

### Inputs

Required inputs:

- `volumes` as `map(object(...))`

Each volume object includes:

- `name` (`string`)
- `catalog_name` (`string`)
- `schema_name` (`string`)
- `volume_type` (`string`): must be `MANAGED` or `EXTERNAL`
- `comment` (`optional(string)`)
- `owner` (`optional(string)`)
- `storage_location` (`optional(string)`)
- `grants` (`optional(list(object))`) where each grant contains:
  - `principal` (`string`)
  - `privileges` (`list(string)`)

Optional module inputs:

- `enabled` (`bool`, default `true`)

### Outputs

Expose a `volumes` output map keyed by the stable caller key. Each value should include at least:

- `name`
- `catalog_name`
- `schema_name`
- `full_name`
- `volume_type`
- `storage_location`

The output shape should make the created namespace easy for root callers and downstream modules to reference.

For `MANAGED` volumes, `storage_location` should be surfaced as `null` in module outputs.

## Volume Behavior

When `enabled = false`:

- create no resources
- return empty outputs

When `enabled = true`:

1. Create one `databricks_volume` resource per `volumes` entry.
2. Set `catalog_name`, `schema_name`, `name`, `volume_type`, `comment`, and `owner` directly from input.
3. For `EXTERNAL` volumes, set `storage_location`.
4. For `MANAGED` volumes, omit `storage_location`.
5. For any module-managed volume with non-empty `grants`, create authoritative `databricks_grants`.
6. The module does not expose delete-force semantics because the provider resource does not support them.

## Grants Model

Grant management should mirror the repo pattern already used by `unity_catalog_storage_locations`:

- flatten each `(volume_key, principal, privilege)` tuple
- detect duplicate tuples and fail instead of silently deduplicating
- regroup privileges by principal before rendering `databricks_grants`

Grant ownership rules:

- if a volume declares `grants`, the module manages that volume's grants authoritatively
- grants apply to both `MANAGED` and `EXTERNAL` volumes
- out-of-band grants on that volume are not preserved
- if a principal should retain access, it must appear in the module input

Supported privileges should be limited to the documented volume privilege set supported by the pinned provider version in this repo:

- `ALL_PRIVILEGES`
- `APPLY_TAG`
- `MANAGE`
- `READ_VOLUME`
- `WRITE_VOLUME`

## Validation Rules

The module should fail fast on invalid caller input.

Required validation:

- `name` must be non-empty when enabled
- `catalog_name` must be non-empty when enabled
- `schema_name` must be non-empty when enabled
- `volume_type` must be exactly `MANAGED` or `EXTERNAL`
- `EXTERNAL` volumes must provide a non-empty `storage_location`
- `MANAGED` volumes must not provide `storage_location`
- `principal` must be non-empty for each grant entry
- each grant must contain at least one privilege
- each declared privilege must be in the supported privilege allowlist

Required precondition-style validation:

- duplicate `(volume_key, principal, privilege)` tuples are invalid and must fail clearly
- duplicate fully qualified volume identities `(catalog_name, schema_name, name)` across different stable keys are invalid and must fail clearly

## Workspace Visibility

This module should not manage workspace bindings.

Rationale:

- there is no requirement to make volume visibility independently configurable here
- workspace visibility for volumes is governed by the surrounding Unity Catalog context rather than by a separate binding pattern already established in this repo
- adding binding logic here would expand scope beyond the approved module boundary

## Failure Modes

Expected runtime failure cases that remain outside Terraform static validation:

- referenced `catalog_name` or `schema_name` does not exist
- external volume `storage_location` is unauthorized or otherwise invalid in Databricks
- caller relies on out-of-band grants that are later removed by authoritative `databricks_grants`

Destroy contract:

- the module does not expose a `force_destroy` input because the provider resource does not support it
- callers should assume non-empty volume deletion is intentionally conservative

Expected caller responsibilities:

- ensure the referenced catalog and schema already exist
- ensure any `EXTERNAL` volume `storage_location` is valid for the target workspace, lies under a pre-existing external location, and has the required privileges in place before volume creation
- keep stable Terraform keys stable to avoid unnecessary address churn
- manage prerequisite ordering in the root caller when related catalogs, schemas, external locations, or grants are created in the same Terraform stack

## Testing And Verification

Module verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate`

Repo formatting:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`

Root verification:

- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`

Negative-path validation checks should cover:

- invalid `volume_type`
- missing `storage_location` for `EXTERNAL`
- forbidden `storage_location` for `MANAGED`
- blank `principal`
- empty privilege lists
- invalid privilege names
- duplicate grant tuples
- duplicate fully qualified volume identities

## Implementation Notes For Planning

Expected module files:

- `SPEC.md`
- `README.md`
- `versions.tf`
- `variables.tf`
- `main.tf`
- `outputs.tf`
- optional `FACTS.md` only if a small fact ledger is needed during implementation

Likely root integration shape:

- a new root config file defining volume inputs and module invocation
- provider wiring should follow the existing pattern used by workspace-scoped Databricks modules
- root callers should prefer passing prerequisite names from upstream outputs and should add explicit `depends_on` when prerequisite authorization exists without a direct data reference

The implementation plan should preserve a clean separation between:

- volume creation concerns
- authoritative grant modeling
- root caller configuration and examples
