# Personal Infra Retirement Runbook

`sandbox-infra` is the active baseline for this root. This runbook is one-time retirement guidance only for decommissioning historical `personal-infra` assets, and it must not be reused as a normal operating path or treated as support for `personal-infra` as an active environment.

## Do not start here

- Do not run `terraform destroy` from the default local state.
- Do not run `terraform destroy` from the sandbox backend.
- Do not run a destroy apply unless both the inventory script and the destroy-plan verifier have been run first.

## Files used in this workflow

- `scenario1.premium-existing.tfvars`
- `personal-infra-retirement.local.tfbackend`
- `personal-infra-retirement-contract.md`
- `render_personal_infra_retirement_inventory.sh`
- `verify_personal_infra_retirement_destroy_plan.sh`

## Path A: Recover Historical Retirement State

Initialize Terraform against the retirement-only local backend, push the recovered historical state into that backend, confirm the retirement state is populated, and render the managed-resource inventory for review.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state push /absolute/path/to/personal-infra-historical.tfstate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh > /tmp/personal-infra-retirement-inventory.md
```

Expected: `state list` shows a non-empty retirement state and the inventory script emits a reviewable list of managed resources.

After the inventory is rendered, prune any preserved or uncertain entries out of the retirement state before planning destroy. Use `terraform state rm` only to stop Terraform from managing the object in the retirement workflow; it does not delete the remote object.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state rm 'module.unity_catalog_metastore_creation.databricks_metastore.this[0]'
```

Any object that should be preserved under the contract, any object with `sandbox` markers, and any object whose ownership is still uncertain must be removed from retirement state and handled outside automated destroy.

After the retirement state has been pruned, regenerate `/tmp/personal-infra-retirement-inventory.md` so the inventory used during final review matches the actual destroy input state.

```bash
infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh > /tmp/personal-infra-retirement-inventory.md
```

## Path B: Reconstruct Retirement State By Import

Use this path only when no trustworthy historical `personal-infra` state can be recovered. Start from the same retirement-only backend and confirm that there are no retirement resources loaded before any import. On a fresh local backend, `terraform state list` may print `No state file was found!`; that still indicates an empty retirement state rather than backend contamination.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Require `terraform state list` to be empty before the first import.

Import only the current-root addresses below, in this order, when each object is provably `personal-infra`-owned:

1. `aws_iam_role.cross_account_role`
2. `aws_iam_role_policy.cross_account`
3. `aws_s3_bucket.root_storage_bucket`
4. `aws_s3_bucket_versioning.root_bucket_versioning`
5. `aws_s3_bucket_server_side_encryption_configuration.root_storage_bucket_sse_s3[0]`
6. `aws_s3_bucket_public_access_block.root_storage_bucket`
7. `aws_s3_bucket_policy.root_bucket_policy`
8. `module.databricks_mws_workspace.databricks_mws_credentials.this`
9. `module.databricks_mws_workspace.databricks_mws_storage_configurations.this`
10. `module.databricks_mws_workspace.databricks_mws_workspaces.workspace`
11. `module.network_connectivity_configuration.databricks_mws_network_connectivity_config.ncc`
12. `module.network_policy.databricks_account_network_policy.restrictive_network_policy`
13. `module.log_delivery[0].aws_s3_bucket.log_delivery`
14. `module.log_delivery[0].aws_s3_bucket_public_access_block.log_delivery`
15. `module.log_delivery[0].aws_s3_bucket_versioning.log_delivery_versioning`
16. `module.log_delivery[0].aws_s3_bucket_policy.log_delivery`
17. `module.log_delivery[0].aws_iam_role.log_delivery`
18. `module.log_delivery[0].databricks_mws_credentials.log_writer`
19. `module.log_delivery[0].databricks_mws_storage_configurations.log_bucket`
20. `module.log_delivery[0].databricks_mws_log_delivery.audit_logs`
21. `module.unity_catalog_metastore_assignment.databricks_metastore_assignment.default_metastore`
22. `module.user_assignment.databricks_mws_permission_assignment.workspace_access`

Only document or run import commands whose resource-specific import IDs have been verified in the provider docs; do not guess Databricks import ID formats.

Recovered historical state may also contain `module.databricks_mws_workspace.null_resource.previous`, `module.databricks_mws_workspace.time_sleep.wait_30_seconds`, or `module.log_delivery[0].time_sleep.wait`. These are state-only helper resources that are safe to let Terraform delete if they appear in Path A, but they should not be imported in Path B.

Anything not on the checklist, or anything whose ownership is still uncertain, stays out of Terraform state and moves to manual adjudication.

After the import set is complete, render the same inventory used in Path A and review it before destroy planning.

```bash
infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh > /tmp/personal-infra-retirement-inventory.md
```

## Generate, Verify, Review, And Apply The Destroy Plan

Generate the destroy plan from the retirement backend with the historical `personal-infra` scenario file, verify it mechanically, review the full plan output, and apply only if the inventory and plan both match the retirement contract.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -destroy -var-file=scenario1.premium-existing.tfvars -out=personal-infra-retirement.destroy.tfplan
infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.destroy.tfplan
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color personal-infra-retirement.destroy.tfplan
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply personal-infra-retirement.destroy.tfplan
```

Before `apply`, the human must compare the refreshed `/tmp/personal-infra-retirement-inventory.md` and the full `terraform show -no-color personal-infra-retirement.destroy.tfplan` output against `personal-infra-retirement-contract.md`. Treat the verifier script output as an additional guardrail, not as the complete review artifact. Reject the plan if it deletes preserved shared resources, includes any create or replace action, references `sandbox`, includes any delete address outside the approved destroy-through-retirement-state scope, or includes anything whose ownership is still uncertain.

## Post-Destroy Verification

After apply completes, confirm the retirement state is empty, switch back to the sandbox backend, and verify the active baseline still plans cleanly. If `terraform state list` prints `No state file was found!` after destroy, that still indicates an empty retirement backend.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected:

- the retirement backend `state list` is empty after destroy
- the operator manually confirms the shared metastore still exists after destroy
- the operator manually confirms `sandbox-infra` remains assigned to the shared metastore and is still usable after destroy
- the sandbox plan succeeds and does not propose destructive drift
- the operator manually confirms the old `personal-infra` workspace no longer exists in the Databricks account UI or API
