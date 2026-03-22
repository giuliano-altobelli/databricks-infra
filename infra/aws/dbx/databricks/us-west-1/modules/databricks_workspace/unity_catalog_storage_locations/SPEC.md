# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_storage_locations`
- **One-liner**: Manage workspace-scoped Unity Catalog S3 storage credentials, external locations, authoritative grants, and explicit workspace bindings.

## Scope

- In scope:
  - Creating Databricks Unity Catalog storage credentials from caller-supplied AWS IAM role ARNs
  - Creating Databricks Unity Catalog external locations that reference those credentials
  - Managing authoritative `databricks_grants` ACLs for the managed storage credentials and external locations
  - Managing explicit `databricks_workspace_binding` resources when isolation mode is workspace-restricted
  - Failing fast on invalid caller input for missing credential references, invalid isolation modes, invalid privilege names, empty privilege lists, duplicate grant tuples, and duplicate workspace binding tuples
- Out of scope:
  - Creating or updating AWS IAM roles, trust policies, S3 buckets, or bucket policies
  - Account-level Databricks resources or provider aliases
  - Multi-provider fan-out from one module invocation
  - Catalog creation or catalog-level grants

## Current Stack Usage

- `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf` is the root caller and configuration catalog for this module.
- The caller passes the workspace-scoped `databricks.created_workspace` provider alias and the already-resolved `local.workspace_id`.
- This rollout is Databricks-only. AWS ownership stays outside the module, but the module surfaces `external_id` and `unity_catalog_iam_arn` so a companion AWS stack can patch IAM trust after the Databricks-side storage credential exists.

## Interfaces

- Required inputs:
  - `current_workspace_id` (`string`): current workspace ID used to compute isolated-mode bindings
  - `storage_credentials` (`map(object)`): storage credential catalog keyed by stable Terraform identifiers. Each value contains:
    - `name` (`string`)
    - `role_arn` (`string`)
    - `comment` (`optional(string)`)
    - `owner` (`optional(string)`)
    - `read_only` (`optional(bool, false)`)
    - `skip_validation` (`optional(bool, false)`)
    - `force_destroy` (`optional(bool, false)`)
    - `force_update` (`optional(bool, false)`)
    - `workspace_access_mode` (`optional(string, "ISOLATION_MODE_ISOLATED")`)
    - `workspace_ids` (`optional(list(string), [])`)
    - `grants` (`optional(list(object))`) where each grant contains:
      - `principal` (`string`)
      - `privileges` (`list(string)`)
  - `external_locations` (`map(object)`): external location catalog keyed by stable Terraform identifiers. Each value contains:
    - `name` (`string`)
    - `url` (`string`)
    - `credential_key` (`string`): stable key of a storage credential declared in `storage_credentials`
    - `comment` (`optional(string)`)
    - `owner` (`optional(string)`)
    - `read_only` (`optional(bool, false)`)
    - `skip_validation` (`optional(bool, false)`)
    - `fallback` (`optional(bool, false)`)
    - `encryption_details` (`optional(object)`) with AWS `sse_encryption_details`
    - `workspace_access_mode` (`optional(string, "ISOLATION_MODE_ISOLATED")`)
    - `workspace_ids` (`optional(list(string), [])`)
    - `grants` (`optional(list(object))`) with `principal` and `privileges`
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module becomes a no-op and all outputs collapse to empty maps
- Outputs:
  - `storage_credentials`: map of stable credential keys to:
    - `name`
    - `databricks_id`
    - `external_id`
    - `unity_catalog_iam_arn`
  - `external_locations`: map of stable external location keys to:
    - `name`
    - `url`
    - `credential_name`

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - Workspace-scoped authentication already configured in the root module; repo verification uses `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - Workspace-level only. This module must not use `databricks.mws` or any account-scoped provider alias.

## Behavior / Data Flow

- When `enabled = false`, the module creates no resources and all outputs are empty maps.
- When `enabled = true`:
  1. The module creates one `databricks_storage_credential` per storage credential key.
  2. It creates one `databricks_external_location` per external location key and resolves `credential_key` to the storage credential name.
  3. It normalizes grant tuples for duplicate detection and groups privileges by principal before creating authoritative `databricks_grants` resources.
  4. For `workspace_access_mode = "ISOLATION_MODE_ISOLATED"`, it computes `effective_workspace_ids = distinct(current_workspace_id + workspace_ids)`.
  5. It creates one `databricks_workspace_binding` per effective isolated binding tuple for storage credentials and external locations.
  6. For `workspace_access_mode = "ISOLATION_MODE_OPEN"`, it creates no workspace bindings and requires `workspace_ids = []`.
  7. It exposes Databricks-generated AWS trust outputs from each storage credential for external IAM orchestration.

## Constraints and Failure Modes

- Stable caller keys are the Terraform identity for managed securables. Renaming a key changes resource addresses even if the Databricks display name stays the same.
- `credential_key` references must target an existing storage credential key in the same module call.
- Supported workspace access modes are exactly `ISOLATION_MODE_ISOLATED` and `ISOLATION_MODE_OPEN`.
- `ISOLATION_MODE_OPEN` does not allow caller-supplied `workspace_ids`.
- This rollout intentionally omits `access_point` because the provider version resolved in this repo does not expose that argument in the installed `databricks_external_location` schema.
- Storage credential grants must use documented storage-credential privilege names.
- External location grants must use documented external-location privilege names.
- Duplicate grant tuples are invalid and must fail clearly rather than silently deduplicating.
- Duplicate workspace binding tuples are invalid and must fail clearly rather than silently deduplicating.
- Grant entries must not contain empty privilege lists.
- `databricks_grants` is authoritative for each managed securable. Out-of-band grants on those securables are not preserved.
- The module does not wait for or patch AWS IAM trust updates. If trust is not ready yet, callers must use `skip_validation = true`, update IAM externally, then re-enable validation.

## Validation

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- Root verification from `infra/aws/dbx/databricks/us-west-1`:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
  - negative-path checks for missing `credential_key`, open mode plus `workspace_ids`, duplicate grant tuples, duplicate workspace bindings, empty privilege lists, invalid privilege names, and invalid isolation mode values
