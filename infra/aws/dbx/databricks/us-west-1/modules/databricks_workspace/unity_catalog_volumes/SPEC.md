# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_volumes`
- **One-liner**: Manage workspace-scoped Unity Catalog managed and external volumes plus optional authoritative volume grants.

## Scope

- In scope:
  - Creating workspace-scoped Databricks Unity Catalog `MANAGED` and `EXTERNAL` volumes
  - Managing authoritative `databricks_grants` resources for module-managed volumes when grants are declared
  - Failing fast on invalid caller input for empty required fields, invalid volume types, invalid storage-location combinations, invalid privileges, duplicate grant tuples, and duplicate fully qualified volume identities
  - Exposing a stable output map for created volumes keyed by caller-defined stable identifiers
- Out of scope:
  - Creating or managing catalogs, schemas, external locations, or storage credentials
  - Workspace bindings, account-level Databricks resources, or `databricks.mws`
  - AWS resource creation or path bootstrap outside Databricks

## Interfaces

- Required inputs:
  - `volumes` (`map(object)`): Unity Catalog volumes keyed by stable caller-defined identifiers. Each value contains:
    - `name` (`string`)
    - `catalog_name` (`string`)
    - `schema_name` (`string`)
    - `volume_type` (`string`)
    - `comment` (`optional(string)`)
    - `owner` (`optional(string)`)
    - `storage_location` (`optional(string)`)
    - `grants` (`optional(list(object)), []`) with:
      - `principal` (`string`)
      - `privileges` (`list(string)`)
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module becomes a no-op and returns empty outputs
- Outputs:
  - `volumes`: map keyed by the stable caller key. Each value includes:
    - `name`
    - `catalog_name`
    - `schema_name`
    - `full_name`
    - `volume_type`
    - `storage_location` with `null` for `MANAGED` volumes

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - Workspace-scoped Databricks authentication provided by the root module; repo verification uses `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - Workspace-level only

## Constraints

- Provider scope: workspace-level only
- `volume_type` must be `MANAGED` or `EXTERNAL`
- `EXTERNAL` volumes require `storage_location`
- `MANAGED` volumes forbid `storage_location`
- grants are authoritative when declared
- duplicate grant tuples and duplicate fully qualified volume identities must fail clearly
- the provider does not expose force-delete behavior for volumes, so the module cannot override conservative deletion semantics
- Stable caller keys are the Terraform identity for managed volumes. Renaming a key changes the Terraform address even if the Databricks volume name stays the same.
- The module references catalog, schema, and external-location paths by name or URI only. Callers must enforce prerequisite ordering when those objects are managed in the same root stack.
- Supported grant privileges are limited to `ALL_PRIVILEGES`, `APPLY_TAG`, `MANAGE`, `READ_VOLUME`, and `WRITE_VOLUME`.

## Validation

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- Root verification from `infra/aws/dbx/databricks/us-west-1`:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
  - negative-path checks for invalid `volume_type`, missing or forbidden `storage_location`, blank principals, empty privilege lists, invalid privileges, duplicate grant tuples, and duplicate fully qualified volume identities
