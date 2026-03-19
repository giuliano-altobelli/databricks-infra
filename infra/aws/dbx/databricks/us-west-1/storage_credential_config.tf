# =============================================================================
# Databricks Unity Catalog Storage Credentials And External Locations
# =============================================================================

locals {
  uc_storage_credentials = {
    # bronze_raw = {
    #   name            = "sandbox-bronze-raw-storage-credential"
    #   role_arn        = "arn:aws:iam::123456789012:role/databricks-sandbox-bronze-raw"
    #   comment         = "Sandbox storage credential for the bronze raw landing bucket."
    #   owner           = "account users"
    #   skip_validation = true
    #   workspace_ids   = ["1234567890123456"]
    #   grants = [
    #     {
    #       principal  = "Sandbox Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #   ]
    # }
    #
    # shared_reporting = {
    #   name                  = "sandbox-shared-reporting-storage-credential"
    #   role_arn              = "arn:aws:iam::123456789012:role/databricks-sandbox-shared-reporting"
    #   comment               = "Sandbox storage credential shared across all workspaces on the metastore."
    #   workspace_access_mode = "ISOLATION_MODE_OPEN"
    #   grants = [
    #     {
    #       principal  = "Sandbox Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #   ]
    # }
    #
    # Auto Loader example:
    # - Reuse one storage credential for both the source prefix and the checkpoint volume backing prefix.
    # - Grant CREATE_EXTERNAL_LOCATION to a placeholder admin or automation principal that will define the external locations.
    #
    # autoloader_ingest = {
    #   name            = "sandbox-autoloader-ingest-storage-credential"
    #   role_arn        = "arn:aws:iam::123456789012:role/databricks-sandbox-autoloader-ingest"
    #   comment         = "Sandbox storage credential for Auto Loader source files and checkpoint-volume backing storage."
    #   skip_validation = true
    #   grants = [
    #     {
    #       principal  = "11111111-1111-1111-1111-111111111111" # Placeholder admin or automation principal application ID
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #   ]
    # }
  }

  uc_external_locations = {
    # bronze_raw_root = {
    #   name           = "sandbox-bronze-raw-root"
    #   url            = "s3://company-sandbox-bronze-raw/"
    #   credential_key = "bronze_raw"
    #   comment        = "Sandbox root prefix for bronze raw datasets."
    #   workspace_ids  = ["1234567890123456"]
    #   grants = [
    #     {
    #       principal  = "Sandbox Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_TABLE"]
    #     }
    #   ]
    # }
    #
    # bronze_raw_curated = {
    #   name           = "sandbox-bronze-raw-curated"
    #   url            = "s3://company-sandbox-bronze-raw/curated/"
    #   credential_key = "bronze_raw"
    #   comment        = "A second sandbox external location reusing the same storage credential."
    # }
    #
    # Auto Loader S3 source + checkpoint volume pattern:
    # - Source ingest path: external location with READ_FILES for the Auto Loader service principal
    # - Checkpoint/schema tracking path: backing external location only, with CREATE_EXTERNAL_VOLUME for the principal that creates the volume
    # - Runtime checkpoint access moves to the external volume grants, so the backing location does not keep READ_FILES/WRITE_FILES runtime grants
    #
    # autoloader_source = {
    #   name           = "sandbox-autoloader-source"
    #   url            = "s3://company-sandbox-bronze-raw/incoming/orders/"
    #   credential_key = "autoloader_ingest"
    #   comment        = "Sandbox Auto Loader source prefix. The service principal reads inbound files from this external location."
    #   grants = [
    #     {
    #       principal  = "00000000-0000-0000-0000-000000000000" # Databricks Auto Loader service principal application ID
    #       privileges = ["READ_FILES"]
    #     }
    #   ]
    # }
    #
    # autoloader_checkpoint_root = {
    #   name           = "sandbox-autoloader-checkpoint-root"
    #   url            = "s3://company-sandbox-bronze-raw/_autoloader/orders/"
    #   credential_key = "autoloader_ingest"
    #   comment        = "Sandbox backing prefix for Auto Loader checkpoint and schema tracking volumes."
    #   grants = [
    #     {
    #       principal  = "11111111-1111-1111-1111-111111111111" # Placeholder admin or automation principal application ID
    #       privileges = ["CREATE_EXTERNAL_VOLUME"]
    #     }
    #   ]
    # }
    #
    # shared_reporting_root = {
    #   name                  = "sandbox-shared-reporting-root"
    #   url                   = "s3://company-sandbox-shared-reporting/"
    #   credential_key        = "shared_reporting"
    #   comment               = "Sandbox open external location visible to every workspace on the shared metastore."
    #   workspace_access_mode = "ISOLATION_MODE_OPEN"
    #   grants = [
    #     {
    #       principal  = "Sandbox Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_TABLE"]
    #     }
    #   ]
    # }
  }
}

module "unity_catalog_storage_locations" {
  source = "./modules/databricks_workspace/unity_catalog_storage_locations"

  providers = {
    databricks = databricks.created_workspace
  }

  current_workspace_id = local.workspace_id
  storage_credentials  = local.uc_storage_credentials
  external_locations   = local.uc_external_locations

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups
  ]
}
