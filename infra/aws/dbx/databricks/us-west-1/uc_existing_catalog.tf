resource "databricks_default_namespace_setting" "existing_catalog_default_namespace" {
  count    = local.effective_uc_catalog_mode == "existing" ? 1 : 0
  provider = databricks.created_workspace

  namespace {
    value = var.uc_existing_catalog_name
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}

resource "databricks_grant" "existing_catalog_admin_grant" {
  count    = local.effective_uc_catalog_mode == "existing" ? 1 : 0
  provider = databricks.created_workspace

  catalog    = var.uc_existing_catalog_name
  principal  = var.admin_user
  privileges = ["ALL_PRIVILEGES"]

  depends_on = [module.unity_catalog_metastore_assignment]
}
