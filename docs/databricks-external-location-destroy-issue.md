# Databricks External Location Destroy Issue

## Summary

We observed a Unity Catalog teardown failure where Terraform successfully destroyed managed volumes, schemas, and the catalog, but then failed while deleting the catalog bootstrap external location.

The same external location could be deleted successfully with the Databricks CLI using `--force`. After that manual CLI delete, a subsequent Terraform plan/apply completed successfully.

## Context

The affected catalog uses:

- `catalog_type = "standard_governed"`
- two managed volumes:
  - `<catalog>.raw.managed_files`
  - `<catalog>.raw_staging.dlt_staging_volume`

The intended Terraform destroy order is:

1. Managed volumes
2. Schemas
3. Catalog
4. Catalog bootstrap external location and related storage resources

Terraform reported successful destroy for the managed volumes and schemas.

## Terraform Error

Terraform later failed while deleting the external location:

```text
Error: cannot delete external location:
Cannot delete external location (name=..., id=..., url=...)
because the location has
0 dependent metastores,
0 dependent catalogs,
0 dependent schemas,
0 dependent managed tables,
0 dependent external tables,
2 dependent managed volumes,
0 dependent registered model versions,
0 dependent shares,
0 dependent shared notebook files.

You may use force option to delete it but the managed storage data under this location cannot be purged by Unity Catalog anymore.
```

## Verification

After the Terraform failure:

- The catalog no longer existed.
- CLI checks for the volumes returned a "catalog does not exist" error, which is expected because the catalog namespace was gone.
- The two managed volumes were not visible as live Unity Catalog volume objects.
- Databricks still reported `2 dependent managed volumes` when deleting the external location.

This suggests the remaining dependency is likely retained managed-volume storage metadata or retained managed data under the external location, not live Unity Catalog volume objects.

## Provider Versus CLI Behavior

We confirmed the installed Databricks Terraform provider schema supports `databricks_external_location.force_destroy`.

We also updated Terraform configuration so the relevant external location resources set or support `force_destroy = true`.

Observed behavior:

- Terraform provider delete with `force_destroy = true` still failed.
- Databricks CLI delete with `--force` succeeded:

```bash
databricks external-locations delete <external-location-name> --force
```

After the CLI force delete, the next Terraform plan/apply completed successfully and cleaned up the remaining destroy.

## Key Finding

There appears to be a behavior difference between:

- Terraform provider deleting `databricks_external_location` with `force_destroy = true`
- Databricks CLI deleting the same external location with `--force`

The CLI force delete succeeds in a state where the Terraform provider delete fails.

## Questions For Databricks

1. Is `databricks_external_location.force_destroy = true` expected to behave identically to `databricks external-locations delete <name> --force`?
2. If yes, why would the Terraform provider fail while CLI `--force` succeeds?
3. When a managed volume is destroyed, why does external location deletion still report dependent managed volumes even though the catalog and volume namespace objects are gone?
4. Is there a supported way to fully purge or bypass managed-volume retention metadata for teardown workflows?
5. Is the reported `2 dependent managed volumes` referring to retained managed storage data rather than active Unity Catalog volume objects?
6. Is this expected behavior, a Terraform provider bug, or an API inconsistency?

## Current Workaround

When Terraform destroy fails on the external location:

```bash
databricks external-locations delete <external-location-name> --force

terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=terraform.tfvars
```

Use the repo's auth wrapper if needed:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 \
  terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
```

After the CLI force delete, Terraform refreshes successfully and finishes the destroy/apply cleanly.

## Notes

- Do not use schema `force_destroy` as the normal workaround. It can delete child Unity Catalog objects behind Terraform's back and leave Terraform state drift for managed volumes.
- For existing external locations, `force_destroy = true` must be applied while the external location still exists. Removing or disabling the resource in the same change can destroy from old Terraform state where `force_destroy` was still `false` or `null`.
