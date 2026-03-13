# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_catalog_creation`
- **One-liner**: Create one AWS-backed, workspace-isolated Unity Catalog catalog plus its directly required storage bootstrap, bindings, and authoritative catalog grants.

## Scope

- In scope:
  - single-catalog module only
  - owns AWS bootstrap plus Databricks storage credential, external location, catalog, bindings, and admin grant
  - workspace-level Databricks provider only
  - optional extra isolated `workspace_ids`
  - no open/shared mode in this change
  - legacy isolated caller must preserve names and state shape
  - optional default-namespace change only when `set_default_namespace = true`
  - deterministic scalar outputs for downstream root aggregation
- Out of scope:
  - multi-catalog fan-out from one module invocation
  - schema, table, volume, or object provisioning
  - schema-level or object-level grants
  - account-level Databricks resources or `databricks.mws`
  - replacing or deleting the legacy isolated root caller in this change

## Current Stack Usage

- The existing isolated path in [main.tf](/Users/giulianoaltobelli/workbench/git-projects/databricks-infra/infra/aws/dbx/databricks/us-west-1/main.tf) calls this module once and wires the workspace-scoped `databricks.created_workspace` provider alias.
- The governed catalog rollout adds a new root caller in `catalogs_config.tf` that fans out one module instance per derived catalog while preserving the legacy isolated caller for backward compatibility.
- Root callers must keep the baseline dependency contract `depends_on = [module.unity_catalog_metastore_assignment, module.users_groups]` and extend it rather than replacing it when later work adds more prerequisites.

## Interfaces

- Required inputs:
  - `aws_account_id` (`string`)
  - `aws_iam_partition` (`string`)
  - `aws_assume_partition` (`string`)
  - `unity_catalog_iam_arn` (`string`)
  - `cmk_admin_arn` (`string`)
  - `resource_prefix` (`string`)
  - `workspace_id` (`string`)
  - `catalog_name` (`string`)
  - `catalog_admin_principal` (`string`)
- Optional inputs:
  - `enabled` (`bool`, default `true`)
  - `catalog_reader_principals` (`list(string)`, default `[]`)
  - `workspace_ids` (`list(string)`, default `[]`)
  - `set_default_namespace` (`bool`, default `false`)
- Outputs:
  - `catalog_name`
  - `catalog_bucket_name`
  - `storage_credential_name`
  - `storage_credential_external_id`
  - `storage_credential_unity_catalog_iam_arn`
  - `external_location_name`
  - `iam_role_arn`
  - `kms_key_arn`
- Output contract when `enabled = false`:
  - the module creates no resources
  - every scalar output listed above returns `null`
  - the root governed-catalog caller is responsible for collapsing its aggregated `catalogs` output to `{}` when no catalogs are enabled

## Provider Context

- Provider(s):
  - `aws` from the root default AWS provider
  - `databricks` wired explicitly as `providers = { databricks = databricks.created_workspace }`
- Authentication mode:
  - workspace-scoped Databricks authentication supplied by the root module; repo verification uses `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - workspace-level only
  - this module must not use `databricks.mws`

## Behavior / Data Flow

- Derived naming:
  - `catalog_name` is the authoritative Databricks catalog identity
  - AWS-safe identifiers derive from `replace(catalog_name, "_", "-")`
  - the computed AWS-safe suffix feeds the bucket, IAM, KMS alias, storage credential, and external location names; the design does not permit silent truncation or hashing
- When `enabled = false`, the module is a true no-op and returns `null` for every scalar output.
- When `enabled = true`, the module follows the approved one-pass bootstrap sequence:
  1. Create the AWS KMS key and alias for the catalog bucket.
  2. Create the Databricks storage credential first using the planned IAM role ARN so Databricks emits `external_id` and `unity_catalog_iam_arn`.
  3. Build the AWS IAM assume-role policy and Unity Catalog access policy inputs from those trust values.
  4. Create the IAM role, IAM policy, and policy attachment.
  5. Create the S3 bucket plus encryption and public-access settings.
  6. Create the Databricks external location for the bucket root.
  7. Create the Databricks catalog with workspace-isolated visibility.
  8. Create explicit `databricks_workspace_binding` resources for the storage credential, external location, and catalog.
  9. Create one authoritative catalog admin grant set for `catalog_admin_principal`.
  10. Skip default-namespace changes unless `set_default_namespace = true`.
- Bootstrap contract:
  - preserve the current single-apply bootstrap pattern
  - do not introduce a caller-facing staged apply or `skip_validation` toggle
  - keep the internal wait and ordering guard between IAM readiness and external-location validation
  - treat first-apply bootstrap failures as implementation defects against the approved one-pass contract
- Workspace binding behavior:
  - the creating workspace is always bound explicitly even though it created the securables
  - `workspace_ids` adds extra isolated bindings on the same metastore
  - this change does not implement open/shared visibility
- Grant behavior:
  - the governed path manages catalog grants authoritatively through `databricks_grants`
  - `catalog_admin_principal` receives `ALL_PRIVILEGES`
  - each entry in `catalog_reader_principals` receives `USE_CATALOG`
  - the legacy isolated path preserves its existing `databricks_grant` state shape and additive grant semantics by continuing to manage only the legacy bootstrap principal grant
  - out-of-band catalog grants are not preserved on governed catalogs, but legacy isolated catalogs retain the legacy non-authoritative behavior until that path is archived

## Constraints and Failure Modes

- `catalog_name` is the stable single-catalog identity for Databricks resources and derived AWS-safe names. Changing it changes managed object identities.
- The module must preserve legacy isolated caller names, Terraform addresses, and state shape when that caller is remapped to the generic interface.
- The module must not introduce open/shared catalog mode in this rollout.
- Duplicate workspace-binding tuples must fail clearly rather than being silently deduplicated.
- Generated S3, IAM, KMS, and Databricks identifiers must fail early if they exceed provider-specific naming rules or length limits.
- Expected runtime failure cases outside static validation:
  - Databricks storage credential creation fails despite the approved one-pass bootstrap sequence
  - external location creation fails because bucket or IAM permissions are incomplete
  - catalog creation fails because the workspace is not assigned to the target metastore
  - authoritative grant application removes unexpected out-of-band catalog access

## Validation

- Module-level input validation must reject:
  - blank `catalog_name` when enabled
  - blank `catalog_admin_principal` when enabled
  - blank or duplicate `catalog_reader_principals` entries when enabled
  - blank or non-numeric `workspace_id` when enabled
  - blank or non-numeric entries in `workspace_ids`
  - duplicate workspace-binding tuples
  - invalid generated S3 bucket names
  - generated AWS or Databricks identifiers that exceed provider name limits
- Verification commands:
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation init -backend=false`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation validate`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
  - root verification from `infra/aws/dbx/databricks/us-west-1`:
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
    - exercise the governed fan-out in a scratch copy or temporary local edit by adding a minimal additional non-`personal` `local.governed_catalog_domains` example alongside the checked-in `personal` catalog baseline
