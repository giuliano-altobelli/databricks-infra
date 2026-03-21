# Personal Infra Retirement Contract

## Preserve

- Databricks account container and account-scoped configuration that serves multiple workspaces
- The shared Unity Catalog metastore itself
- Existing Okta SCIM-provisioned users and the SCIM-managed `okta-databricks-users` access path

## Destroy Through Retirement State

Only the following current-root-managed addresses are approved for destroy through retirement state, and only when each object is provably `personal-infra`-owned:

- `aws_iam_role.cross_account_role`
- `aws_iam_role_policy.cross_account`
- `aws_s3_bucket.root_storage_bucket`
- `aws_s3_bucket_versioning.root_bucket_versioning`
- `aws_s3_bucket_server_side_encryption_configuration.root_storage_bucket_sse_s3[0]`
- `aws_s3_bucket_public_access_block.root_storage_bucket`
- `aws_s3_bucket_policy.root_bucket_policy`
- `module.databricks_mws_workspace.null_resource.previous`
- `module.databricks_mws_workspace.time_sleep.wait_30_seconds`
- `module.databricks_mws_workspace.databricks_mws_credentials.this`
- `module.databricks_mws_workspace.databricks_mws_storage_configurations.this`
- `module.databricks_mws_workspace.databricks_mws_workspaces.workspace`
- `module.network_connectivity_configuration.databricks_mws_network_connectivity_config.ncc`
- `module.network_policy.databricks_account_network_policy.restrictive_network_policy`
- `module.log_delivery[0].aws_s3_bucket.log_delivery`
- `module.log_delivery[0].aws_s3_bucket_public_access_block.log_delivery`
- `module.log_delivery[0].aws_s3_bucket_versioning.log_delivery_versioning`
- `module.log_delivery[0].aws_s3_bucket_policy.log_delivery`
- `module.log_delivery[0].aws_iam_role.log_delivery`
- `module.log_delivery[0].time_sleep.wait`
- `module.log_delivery[0].databricks_mws_credentials.log_writer`
- `module.log_delivery[0].databricks_mws_storage_configurations.log_bucket`
- `module.log_delivery[0].databricks_mws_log_delivery.audit_logs`
- `module.unity_catalog_metastore_assignment.databricks_metastore_assignment.default_metastore`
- `module.user_assignment.databricks_mws_permission_assignment.workspace_access`

Any delete address outside this approved scope must be rejected unless it has been explicitly adjudicated, added to this contract and the runbook, and then re-reviewed as part of the retirement workflow.

The `null_resource` and `time_sleep` addresses above are state-only helper resources from the current root. They are safe to let Terraform delete when they appear in recovered historical state, but they do not need import-based reconstruction.

## Manual Adjudication Required

- any live object not represented in the retirement state inventory
- any Unity Catalog object on the shared metastore whose ownership cannot be proven from current config, historical state, or `personal-infra` naming
- any object with `sandbox` naming or any known non-`personal-infra` consumer
- any resource whose only safe deletion path would require reintroducing adopt-existing or multi-environment abstractions into the root

## Reject The Destroy Plan If

The human must reject any destroy plan that:

- deletes `databricks_metastore` or `module.unity_catalog_metastore_creation.*`
- references `okta-databricks-users`, `databricks_user`, or any other SCIM-user deletion path
- includes create, update, or replace actions
- includes `sandbox` resource names, addresses, or IDs
- contains resources whose ownership is still uncertain
- includes any delete address outside the approved destroy-through-retirement-state scope above
