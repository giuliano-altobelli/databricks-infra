# =============================================================================
# Databricks Unity Catalog Storage Credentials And External Locations
# =============================================================================

locals {
  uc_storage_credentials = {
    # bronze_raw = {
    #   name            = "bronze-raw-storage-credential"
    #   role_arn        = "arn:aws:iam::123456789012:role/databricks-bronze-raw"
    #   comment         = "Storage credential for the bronze raw landing bucket."
    #   owner           = "account users"
    #   skip_validation = true
    #   workspace_ids   = ["1234567890123456"]
    #   grants = [
    #     {
    #       principal  = "Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #     {
    #       principal  = "Data Engineers"
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #     {
    #       principal  = "00000000-0000-0000-0000-000000000000" # Databricks service principal application ID
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #   ]
    # }
    #
    # shared_reporting = {
    #   name                  = "shared-reporting-storage-credential"
    #   role_arn              = "arn:aws:iam::123456789012:role/databricks-shared-reporting"
    #   comment               = "Open storage credential shared across all workspaces on the metastore."
    #   workspace_access_mode = "ISOLATION_MODE_OPEN"
    #   grants = [
    #     {
    #       principal  = "Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_LOCATION"]
    #     }
    #   ]
    # }
  }

  uc_external_locations = {
    # bronze_raw_root = {
    #   name           = "bronze-raw-root"
    #   url            = "s3://company-bronze-raw/"
    #   credential_key = "bronze_raw"
    #   comment        = "Root prefix for bronze raw datasets."
    #   workspace_ids  = ["1234567890123456"]
    #   grants = [
    #     {
    #       principal  = "Platform Admins"
    #       privileges = ["CREATE_EXTERNAL_TABLE"]
    #     }
    #     {
    #       principal  = "Data Engineers"
    #       privileges = ["CREATE_EXTERNAL_TABLE"]
    #     }
    #   ]
    # }
    #
    # bronze_raw_curated = {
    #   name           = "bronze-raw-curated"
    #   url            = "s3://company-bronze-raw/curated/"
    #   credential_key = "bronze_raw"
    #   comment        = "A second external location reusing the same storage credential."
    # }
    #
    # Auto Loader file events pattern:
    # - Source location: READ_FILES
    # - Checkpoint/schema location: READ_FILES + WRITE_FILES
    # - Catalog/schema/table creation privileges are managed separately
    #
    # autoloader_source = {
    #   name           = "autoloader-source"
    #   url            = "s3://company-bronze-raw/incoming/"
    #   credential_key = "bronze_raw"
    #   comment        = "Auto Loader source prefix. The service principal reads files from this external location."
    #   grants = [
    #     {
    #       principal  = "00000000-0000-0000-0000-000000000000" # Databricks service principal application ID
    #       privileges = ["READ_FILES"]
    #     }
    #   ]
    # }
    #
    # autoloader_checkpoint = {
    #   name           = "autoloader-checkpoint"
    #   url            = "s3://company-bronze-raw/_checkpoints/orders/"
    #   credential_key = "bronze_raw"
    #   comment        = "Auto Loader checkpoint and schema tracking prefix. The service principal needs read/write access here."
    #   grants = [
    #     {
    #       principal  = "00000000-0000-0000-0000-000000000000" # Databricks service principal application ID
    #       privileges = ["READ_FILES", "WRITE_FILES"]
    #     }
    #   ]
    # }
    #
    # shared_reporting_root = {
    #   name                  = "shared-reporting-root"
    #   url                   = "s3://company-shared-reporting/"
    #   credential_key        = "shared_reporting"
    #   comment               = "Open external location visible to every workspace on the shared metastore."
    #   workspace_access_mode = "ISOLATION_MODE_OPEN"
    #   grants = [
    #     {
    #       principal  = "Platform Admins"
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
