data "aws_availability_zones" "available" {
  state = "available"
}

data "databricks_current_metastore" "workspace" {
  provider = databricks.created_workspace

  provider_config {
    workspace_id = local.workspace_id
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}

data "databricks_catalogs" "workspace" {
  provider = databricks.created_workspace

  provider_config {
    workspace_id = local.workspace_id
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}
