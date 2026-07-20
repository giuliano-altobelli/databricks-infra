locals {
  tags = {
    reviewed = {
      description = "Indicates that an object has completed review."
    }
    lifecycle = {
      description = "Identifies the lifecycle stage of an object."
      values      = ["development", "production", "retired"]
    }
  }
}

module "governance" {
  source = "./modules/databricks_workspace/unity_catalog_governed_tags"

  providers = {
    databricks = databricks.created_workspace
  }

  tags = local.tags
}
