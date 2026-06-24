terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.84"
    }
  }
  required_version = "~> 1.3"
}
