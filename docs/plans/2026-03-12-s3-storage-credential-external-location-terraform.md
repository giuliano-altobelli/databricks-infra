# S3 Storage Credential / External Location Terraform Plan

Date: 2026-03-12

## Summary

- Add a new workspace-scoped module at `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations` to manage multiple Unity Catalog S3 storage credentials and external locations from Terraform.
- Keep AWS ownership out of this module: it accepts pre-existing `role_arn` and `s3://...` paths, and it exposes storage credential `external_id` / `unity_catalog_iam_arn` outputs so a companion AWS stack can patch IAM trust when needed.
- Do not redesign the root for multi-provider fan-out now. Use the existing `databricks.created_workspace` provider only; the researched Databricks model supports cross-workspace visibility through workspace bindings on the same metastore.
- Research basis:
  - [Terraform `databricks_storage_credential`](https://raw.githubusercontent.com/databricks/terraform-provider-databricks/main/docs/resources/storage_credential.md)
  - [Terraform `databricks_external_location`](https://raw.githubusercontent.com/databricks/terraform-provider-databricks/main/docs/resources/external_location.md)
  - [Terraform `databricks_workspace_binding`](https://raw.githubusercontent.com/databricks/terraform-provider-databricks/main/docs/resources/workspace_binding.md)
  - [Databricks S3 manual flow](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/s3/s3-external-location-manual)
  - [manage storage credentials](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/manage-storage-credentials)
  - [manage external locations](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/manage-external-locations)

## Implementation Changes

- Create the new module with `SPEC.md`, `FACTS.md`, `variables.tf`, `main.tf`, `outputs.tf`, and `README.md`.
- Module interface:
  - `enabled` default `true`
  - `current_workspace_id` string
  - `storage_credentials` as a stable-keyed `map(object(...))`
  - `external_locations` as a stable-keyed `map(object(...))`
- `storage_credentials` entries should include `name`, `role_arn`, optional `comment`, `owner`, `read_only`, `skip_validation`, `force_destroy`, `force_update`, `workspace_access_mode` default `ISOLATION_MODE_ISOLATED`, `workspace_ids` default `[]`, and optional `grants`.
- `external_locations` entries should include `name`, `url`, `credential_key`, optional `comment`, `owner`, `read_only`, `skip_validation`, `fallback`, `access_point`, optional `encryption_details`, `workspace_access_mode` default `ISOLATION_MODE_ISOLATED`, `workspace_ids` default `[]`, and optional `grants`.
- Module behavior:
  - Create one `databricks_storage_credential` per credential key and one `databricks_external_location` per location key.
  - Use authoritative `databricks_grants` only when grants are declared; out-of-band grants on managed securables are not preserved.
  - For `ISOLATION_MODE_ISOLATED`, compute `effective_workspace_ids = distinct(current_workspace_id + workspace_ids)` and manage explicit `databricks_workspace_binding` resources for every effective workspace. For `ISOLATION_MODE_OPEN`, require `workspace_ids = []`.
  - Validate unknown `credential_key` references, invalid isolation modes, duplicate grant tuples, duplicate binding tuples, and empty privilege lists at plan time.
  - Output per credential: name, Databricks ID, `external_id`, and `unity_catalog_iam_arn`. Output per external location: name, URL, and resolved credential name.
- Add a root caller/config file at `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf` that follows the existing config-local pattern:
  - `local.uc_storage_credentials = {}`
  - `local.uc_external_locations = {}`
  - One fully commented S3 example showing multiple credentials, multiple locations, optional grants, and optional extra `workspace_ids`
  - A module block wired to `databricks.created_workspace` and `local.workspace_id`
- Update `infra/aws/dbx/databricks/us-west-1/README.md` to document:
  - multiple credential/location configuration
  - isolated-by-default vs open-to-all-workspaces behavior
  - cross-workspace sharing through `workspace_ids`
  - AWS bootstrap nuance: if IAM trust is not yet patched with the emitted `external_id`, first create the credential with `skip_validation = true`, update the IAM trust externally, then turn validation back on before relying on the credential for external locations

## Test Plan

- Module checks:
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations init -backend=false`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations validate`
- Root checks:
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
- Negative-path acceptance:
  - external location references a missing `credential_key`
  - `ISOLATION_MODE_OPEN` with non-empty `workspace_ids`
  - duplicate grants on the same securable
  - duplicate workspace bindings on the same securable
  - empty privilege lists
  - invalid isolation mode values

## Assumptions And Defaults

- Scope is `Unity Catalog + workspace`, with optional sharing to additional workspace IDs on the same metastore.
- Existing S3 buckets/prefixes and IAM roles stay outside this change; this module is Databricks-only.
- Grants are optional, but when present they are authoritative for that managed storage credential or external location.
- Default posture is isolated to the current workspace, not metastore-wide open.
- Do not refactor the existing `unity_catalog_catalog_creation` module in this first change; keep its AWS+catalog bootstrap path separate until the new generic module is proven.
