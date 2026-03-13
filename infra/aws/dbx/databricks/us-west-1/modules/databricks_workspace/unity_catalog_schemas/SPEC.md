# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_schemas`
- **One-liner**: Manage workspace-scoped Unity Catalog schemas plus optional schema properties and authoritative schema grants.

## Scope

- In scope:
  - one `databricks_schema` resource per schema entry
  - optional schema `properties` passthrough to `databricks_schema`
  - one authoritative `databricks_grants` resource per schema entry when grants are declared
  - workspace-level Databricks provider only
  - duplicate detection for fully qualified schema identities and grant tuples
  - stable output map for created schemas keyed by caller-defined identifiers
- Out of scope:
  - no catalog creation
  - no volume creation
  - no storage credentials or external locations
  - no account-level resources or `databricks.mws`

## Interfaces

- Required inputs:
  - `schemas` (`map(object)`): Unity Catalog schemas keyed by stable caller-defined identifiers
  - `schemas[*].catalog_name` (`string`)
  - `schemas[*].schema_name` (`string`)
  - `schemas[*].comment` (`optional(string)`)
  - `schemas[*].properties` (`optional(map(string))`)
  - `schemas[*].grants[*].principal` (`string`)
  - `schemas[*].grants[*].privileges` (`list(string)`)
- Optional inputs:
  - `enabled` (`bool`, default `true`)
- Outputs:
  - `schemas`: map keyed by the stable caller key. Each value includes:
    - `catalog_name`
    - `schema_name`
    - `full_name`
- Output contract when `enabled = false`:
  - the module creates no resources
  - the `schemas` output returns `{}`
- The concrete `outputs.tf` implementation follows this contract once `databricks_schema.this` exists in the resource graph.

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - workspace-scoped Databricks authentication supplied by the root module; repo verification uses `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - workspace-level only

## Behavior / Data Flow

- The caller provides a stable-keyed `schemas` map.
- The module creates one `databricks_schema` resource per schema entry and passes through optional schema `properties`.
- In the governed root configuration, schema grants are typically derived upstream from catalog-level identity inputs, so catalog admins and catalog readers receive schema access by default unless a schema entry declares its own `grants`.
- When a schema entry declares `grants`, that list is the full authoritative allow-list for that schema in Terraform; it replaces any upstream-derived default grants rather than merging with them.
- When a schema declares grants, the module flattens `(schema_key, principal, privilege)` tuples, rejects duplicates, regroups privileges by principal, and creates one authoritative `databricks_grants` resource for that schema.
- The output map preserves the caller-defined stable keys and returns the created schema identity through `full_name`.

## Constraints and Failure Modes

- Stable caller keys are the Terraform identity for managed schemas. Renaming a key changes the Terraform address even if the Databricks schema name stays the same.
- Grants are authoritative when declared. Out-of-band schema grants on managed schemas are not preserved.
- Because grants are authoritative, omitting a principal from a schema's explicit `grants` removes that schema access through this Terraform-managed path; this is how schema-specific exclusions are modeled.
- Supported schema grant privileges are limited to `ALL_PRIVILEGES` and `USE_SCHEMA`.
- Expected runtime failures outside static validation include missing catalogs, missing metastore assignment, or provider/runtime rejection of an otherwise syntactically valid request.

## Validation

- Module-level validation must reject:
  - blank `catalog_name`
  - blank `schema_name`
  - blank schema property keys
  - blank grant principals
  - empty privilege lists
  - invalid privilege names
  - duplicate fully qualified schema identities across stable keys
  - duplicate schema grant tuples
- Verification commands:
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas init -backend=false`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
  - root verification from `infra/aws/dbx/databricks/us-west-1`:
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
