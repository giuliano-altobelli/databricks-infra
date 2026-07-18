terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.109.0, < 2.0.0"
    }
  }

  required_version = "~> 1.3"
}
