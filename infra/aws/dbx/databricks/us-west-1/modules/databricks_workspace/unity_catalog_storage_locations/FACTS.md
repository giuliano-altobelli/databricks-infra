# Facts Ledger (Docs -> Durable Facts)

Use this file to keep retrieved documentation out of chat context.

Rules:

- Record only the minimum durable facts needed to implement the module.
- Prefer 1-2 lines per fact; do not paste large doc blocks.
- Always include a source pointer you can re-fetch later.
  - Terraform Registry / raw provider docs
  - Databricks docs pages

## Facts

| Area | Item | Fact (short) | Source | Notes |
| --- | --- | --- | --- | --- |
| resource | `databricks_storage_credential` | Workspace-level providers can manage storage credentials; AWS mode uses `aws_iam_role.role_arn`, optional `owner`, `read_only`, `skip_validation`, `force_destroy`, `force_update`, and `isolation_mode`. | raw: `terraform-provider-databricks/docs/resources/storage_credential.md` | `isolation_mode` values are `ISOLATION_MODE_ISOLATED` or `ISOLATION_MODE_OPEN`. |
| output | `databricks_storage_credential.aws_iam_role` | AWS storage credential exports `external_id` and `unity_catalog_iam_arn` for IAM trust configuration. | raw: `terraform-provider-databricks/docs/resources/storage_credential.md` | Needed for companion AWS automation. |
| databricks docs | storage credential privileges | Databricks recommends granting only `CREATE EXTERNAL LOCATION` on storage credentials. | docs.databricks.com: `manage-storage-credentials` | Example grants should not use `CREATE_EXTERNAL_TABLE` on storage credentials. |
| databricks docs | storage credential privilege names | Documented storage credential privileges are `ALL PRIVILEGES`, `CREATE EXTERNAL LOCATION`, `CREATE EXTERNAL TABLE`, `MANAGE`, `READ FILES`, and `WRITE FILES`. | docs.databricks.com: `unity-catalog/manage-privileges/privileges` | Module validation should allow the documented set, not just the recommended subset. |
| resource | `databricks_external_location` | The installed provider schema in this repo supports `name`, `url`, `credential_name`, ownership/comment/validation flags, `fallback`, optional `encryption_details`, and `isolation_mode`; it does not expose `access_point`. | local provider schema: `terraform providers schema -json` for `databricks_external_location` | AWS encryption examples still use `sse_encryption_details`. |
| resource | `databricks_workspace_binding` | Workspace binding only works for isolated securables; for storage credentials and external locations it requires `securable_name`, `workspace_id`, and `securable_type`. | raw: `terraform-provider-databricks/docs/resources/workspace_binding.md` | Isolated securables are auto-bound to the creating workspace unless bindings are managed explicitly. |
| resource | `databricks_grants` | `databricks_grants` is authoritative for a securable and must contain one securable identifier plus one or more `grant` blocks with `principal` and `privileges`. | raw: `terraform-provider-databricks/docs/resources/grants.md` | Out-of-band grants are overwritten. |
| databricks docs | AWS manual bootstrap | When AWS IAM trust is not fully patched yet, operators can create the storage credential first, then update IAM trust with the Databricks-generated external ID before validating location access. | docs.databricks.com: `s3-external-location-manual` and `manage-storage-credentials` | Root README should explain `skip_validation` for first-pass bootstrap. |
| databricks docs | external location privileges | External locations should usually grant `CREATE EXTERNAL TABLE`, `CREATE EXTERNAL VOLUME`, or managed-location privileges; Databricks recommends avoiding broad `READ FILES` or `WRITE FILES` grants except for intentional path-based access. | docs.databricks.com: `manage-external-locations` and `unity-catalog/best-practices` | Example grants should default to least privilege. |
| databricks docs | external location privilege names | Documented external location privileges are `ALL PRIVILEGES`, `BROWSE`, `CREATE EXTERNAL TABLE`, `CREATE EXTERNAL VOLUME`, `CREATE FOREIGN SECURABLE`, `CREATE MANAGED STORAGE`, `EXTERNAL USE LOCATION`, `MANAGE`, `READ FILES`, and `WRITE FILES`. | docs.databricks.com: `unity-catalog/manage-privileges/privileges` | `CREATE_MANAGED_STORAGE` is the correct managed-storage privilege string. |

## Decisions

- Decision: Keep AWS ownership out of this module and accept pre-existing `role_arn` plus `s3://...` URLs only.
- Rationale: The plan explicitly separates Databricks resource management from companion AWS trust/bucket configuration.
- Consequences: This module exposes Databricks-generated trust outputs but never creates AWS IAM resources.

- Decision: Use authoritative `databricks_grants` only when the caller declares grants.
- Rationale: The plan requires Terraform ownership of grants for managed securables while keeping grants optional.
- Consequences: Out-of-band grants are not preserved on securables with declared grants.

- Decision: Explicitly manage workspace bindings for isolated storage credentials and external locations.
- Rationale: The provider docs state isolated securables are auto-bound to the current workspace, and explicit bindings are the supported path for cross-workspace sharing.
- Consequences: The module must calculate isolated effective workspace IDs and fail fast on invalid or duplicate binding inputs.

## Open Questions

- Question: Does the Databricks provider accept duplicate `grant` principals in multiple blocks if their privilege sets are disjoint?
- Why it matters: The module normalizes grants by principal after validating duplicate principal-privilege tuples to avoid provider ambiguity.
