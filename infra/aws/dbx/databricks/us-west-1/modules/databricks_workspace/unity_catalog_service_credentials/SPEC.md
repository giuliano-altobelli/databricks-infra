# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_service_credentials`
- **One-liner**: Manage AWS-backed Unity Catalog service credentials, authoritative access grants, and optional workspace bindings.

## Scope

- In scope:
  - Creating Unity Catalog service credentials with `databricks_credential` and `purpose = "SERVICE"`
  - AWS IAM role backed service credentials only
  - Managing authoritative `databricks_grants` ACLs for managed service credentials
  - Managing explicit `databricks_workspace_binding` resources when isolation mode is workspace-restricted
  - Exposing Databricks-generated AWS trust outputs for external IAM orchestration
  - Failing fast on invalid role ARNs, invalid workspace access modes, invalid privilege names, duplicate grant tuples, duplicate binding tuples, and invalid workspace IDs
- Out of scope:
  - Creating or updating AWS IAM roles, trust policies, IAM policies, Bedrock permissions, or external-service permissions
  - Azure or GCP service credentials
  - Unity Catalog storage credentials, external locations, catalogs, schemas, tables, volumes, or data grants
  - Databricks users, groups, service principals, service principal credentials, workspace assignments, or entitlements
  - Bedrock model serving endpoints or migration from `instance_profile_arn` to `uc_service_credential_name`
  - Lakehouse Federation connection creation or `CREATE_CONNECTION` grants
  - Importing or adopting existing service credentials
  - Multi-workspace fan-out from one module invocation

## Current Stack Usage

- This module is intended to be called from `infra/aws/dbx/databricks/us-west-1` once a service-credential consumer is ready.
- No root module config is created in this phase.
- Root callers should resolve repo-local group and service-principal keys into Databricks-native principal strings before passing grants into this module.
- The caller passes the workspace-scoped `databricks.created_workspace` provider alias and the already-resolved `local.workspace_id`.
- AWS ownership stays outside this module, but the module surfaces `external_id` and `unity_catalog_iam_arn` so a companion AWS workflow can patch IAM trust after the Databricks-side credential exists.

## Interfaces

- Required inputs:
  - `current_workspace_id` (`string`): current workspace ID used to compute isolated-mode bindings
  - `service_credentials` (`map(object)`): service credential catalog keyed by stable Terraform identifiers. Each value contains:
    - `name` (`string`)
    - `aws.role_arn` (`string`)
    - `comment` (`optional(string)`)
    - `owner` (`optional(string)`)
    - `skip_validation` (`optional(bool, false)`)
    - `force_destroy` (`optional(bool, false)`)
    - `force_update` (`optional(bool, false)`)
    - `workspace_access_mode` (`optional(string, "ISOLATION_MODE_ISOLATED")`)
    - `workspace_ids` (`optional(list(string), [])`)
    - `grants` (`optional(list(object))`) where each grant contains:
      - `principal` (`string`)
      - `privileges` (`optional(list(string), ["ACCESS"])`)
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module becomes a no-op and all outputs collapse to empty maps
- Outputs:
  - `service_credentials`: map of stable service credential keys to:
    - `name`
    - `id`
    - `credential_id`
    - `full_name`
    - `external_id`
    - `unity_catalog_iam_arn`
  - `grant_ids`: map of grant resource IDs keyed by service credential key
  - `workspace_binding_ids`: map of workspace binding IDs keyed by `<credential_key>:<workspace_id>`

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
  1. The module creates one `databricks_credential` per service credential key.
  2. Each credential is created with `purpose = "SERVICE"` and an `aws_iam_role.role_arn`.
  3. It normalizes grant tuples for duplicate detection and groups privileges by principal before creating authoritative `databricks_grants` resources.
  4. For `workspace_access_mode = "ISOLATION_MODE_ISOLATED"`, it computes `effective_workspace_ids = distinct(current_workspace_id + workspace_ids)`.
  5. It creates one `databricks_workspace_binding` per effective isolated binding tuple.
  6. For `workspace_access_mode = "ISOLATION_MODE_OPEN"`, it creates no workspace bindings and requires `workspace_ids = []`.
  7. It exposes Databricks-generated AWS trust outputs from each service credential for external IAM orchestration.

## Constraints and Failure Modes

- Stable caller keys are the Terraform identity for managed service credentials. Renaming a key changes resource addresses even if the Databricks display name stays the same.
- Supported workspace access modes are exactly `ISOLATION_MODE_ISOLATED` and `ISOLATION_MODE_OPEN`.
- `ISOLATION_MODE_OPEN` does not allow caller-supplied `workspace_ids`.
- Service credential grant privileges are restricted to `ACCESS` in this phase.
- Duplicate grant tuples are invalid and must fail clearly rather than silently deduplicating.
- Duplicate workspace binding tuples are invalid and must fail clearly rather than silently deduplicating.
- Grant entries must not contain empty privilege lists.
- Grant principals must be non-empty Databricks-native principal identifiers.
- `databricks_grants` is authoritative for each managed credential. Out-of-band grants on those credentials are not preserved.
- The module does not wait for or patch AWS IAM trust updates. If trust is not ready yet, callers must use `skip_validation = true`, update IAM externally, then re-enable validation.
- `force_destroy = true` is an explicit caller opt-in for teardown paths where Databricks requires force deletion.
- Runtime failures may still occur when:
  - the caller lacks metastore privileges to create service credentials
  - the caller lacks privileges to grant `ACCESS` on a credential
  - the AWS IAM role trust is incomplete and `skip_validation = false`
  - a service credential `name` collides with an existing credential
  - `current_workspace_id` and the wired `databricks` provider point at different workspaces

## Validation

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials test`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- Root verification from `infra/aws/dbx/databricks/us-west-1` when a future root caller is added:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars`
  - negative-path checks for invalid role ARN, open mode plus `workspace_ids`, duplicate grant tuples, duplicate workspace bindings, empty privilege lists, invalid privilege names, blank principals, and invalid isolation mode values
