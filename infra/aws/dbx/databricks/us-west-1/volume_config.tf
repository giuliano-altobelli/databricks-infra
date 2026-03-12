# =============================================================================
# Databricks Unity Catalog Volumes
# =============================================================================

locals {
  uc_volumes = {}

  /*
  uc_volumes = {
    model_artifacts = {
      name         = "model_artifacts"
      catalog_name = "prod_ml_platform"
      schema_name  = "final"
      volume_type  = "MANAGED"
    }
    inbound_files = {
      name             = "inbound_files"
      catalog_name     = "prod_salesforce_revenue"
      schema_name      = "uat"
      volume_type      = "EXTERNAL"
      storage_location = format("%s/volumes/inbound_files/", trimsuffix(module.unity_catalog_storage_locations.external_locations["revenue_raw"].url, "/"))
      grants = [
        {
          principal  = "00000000-0000-0000-0000-000000000000" # UAT promotion service principal application ID
          privileges = ["READ_VOLUME", "WRITE_VOLUME"]
        }
      ]
    }
  }
  */
}

# Ordering contract:
# - Keep the baseline depends_on = [module.unity_catalog_metastore_assignment, module.users_groups].
# - Pass catalog and schema names from upstream resource or module outputs when available.
# - For EXTERNAL volumes, storage_location must live under a pre-existing external location.
# - If external-location readiness is only semantic, extend depends_on.
# - If grants reference additional Terraform-managed groups or service principals, extend depends_on.
# - If Unity Catalog readiness has extra prerequisites in this root, extend depends_on rather than replacing the baseline entries.
#
# Example extension:
# depends_on = [
#   module.unity_catalog_metastore_assignment,
#   module.users_groups,
#   module.upstream_catalogs,
#   module.upstream_storage_locations,
# ]
module "unity_catalog_volumes" {
  source = "./modules/databricks_workspace/unity_catalog_volumes"

  providers = {
    databricks = databricks.created_workspace
  }

  volumes = local.uc_volumes

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
  ]
}
