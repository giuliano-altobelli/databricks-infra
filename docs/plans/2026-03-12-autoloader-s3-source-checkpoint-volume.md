# Auto Loader S3 Source + Checkpoint Volume Example Plan

## Summary
- Keep this change Unity Catalog only and example-only: update the root commented examples, not the live defaults.
- Do not change `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`; the module already supports external volumes. The root caller in `infra/aws/dbx/databricks/us-west-1/volume_config.tf` is what must declare the checkpoint volume.
- Model runtime access as: source S3 prefix via external location with `READ_FILES`, checkpoint/schema tracking via external volume in `workspace.default` with `READ_VOLUME` and `WRITE_VOLUME`.

## Key Changes
- In `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf`, reshape the commented Auto Loader example so it shows:
  - one shared storage credential, e.g. `autoloader_ingest`, with placeholder `role_arn`, `skip_validation = true`, and a placeholder principal granted `CREATE_EXTERNAL_LOCATION`
  - one source external location, e.g. `autoloader_source`, pointing at the inbound S3 prefix and granting the placeholder Auto Loader service principal `READ_FILES`
  - one checkpoint backing external location, e.g. `autoloader_checkpoint_root`, pointing at the checkpoint/schema S3 prefix and granting a placeholder admin/creator principal `CREATE_EXTERNAL_VOLUME`
  - comments explaining that checkpoint runtime access moves to the volume layer, so the checkpoint backing location should not keep the old `READ_FILES`/`WRITE_FILES` example
- In `infra/aws/dbx/databricks/us-west-1/volume_config.tf`, add a commented external-volume example for Auto Loader checkpointing that:
  - uses `catalog_name = "workspace"` and `schema_name = "default"`
  - sets `volume_type = "EXTERNAL"`
  - builds `storage_location` from `module.unity_catalog_storage_locations.external_locations["autoloader_checkpoint_root"].url` plus a child `volumes/...` suffix using the existing `format(... trimsuffix(...))` pattern
  - grants the placeholder Auto Loader service principal `READ_VOLUME` and `WRITE_VOLUME`
  - states that the volume is for checkpoint and schema tracking, not the source ingest path
- Keep all new blocks commented out and use placeholder principal identifiers so the repo stays non-operative by default.

## Interfaces
- No module API, provider alias, or output changes.
- Reuse the existing root local maps `local.uc_storage_credentials`, `local.uc_external_locations`, and `local.uc_volumes` with their current object shapes.

## Test Plan
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
- Verify the examples remain commented, the checkpoint volume references the storage-location module output correctly, and no module schema changes are needed.

## Assumptions
- Scope remains Unity Catalog only; no account-level or workspace-level identity provisioning changes.
- One storage credential backs both the source and checkpoint prefixes.
- The source is accessed directly through an external location, while checkpoint/schema state uses an external volume.
- Placeholder principals and ARNs will be filled later; until then the examples remain commented and explanatory only.
