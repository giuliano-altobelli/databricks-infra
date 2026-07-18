locals {
  abac = {
    (var.abac.name) = {
      scope = {
        catalog = local.derived_governed_catalogs["abac_demo"].catalog_name
      }
      principals = var.abac.principals
      table      = var.abac.table
      columns = {
        first = var.abac.column
      }
      function = join(".", [var.security_catalog_name, var.abac.function.schema, var.abac.function.name])
      comment  = var.abac.comment
    }
  }
}

data "databricks_current_user" "deployment" {
  provider = databricks.created_workspace
}

resource "databricks_grant" "abac" {
  count    = var.enable_abac_demo_catalog ? 1 : 0
  provider = databricks.created_workspace

  function   = one(values(local.abac)).function
  principal  = data.databricks_current_user.deployment.user_name
  privileges = ["EXECUTE"]
}

module "abac_policy" {
  source = "./modules/databricks_workspace/abac_policy"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled = var.enable_abac_demo_catalog
  dependencies = toset([
    for grant in databricks_grant.abac : grant.id
  ])
  policies = local.abac
}
