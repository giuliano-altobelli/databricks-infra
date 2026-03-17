terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      version               = ">=1.84.0"
      configuration_aliases = [databricks.mws, databricks.workspace]
    }
  }
  required_version = ">=1.0"
}
