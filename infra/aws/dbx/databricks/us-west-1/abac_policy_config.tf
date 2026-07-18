data "databricks_current_user" "deployment" {
  provider = databricks.created_workspace
}

resource "databricks_grant" "abac" {
  count    = var.enable_abac_demo_catalog ? 1 : 0
  provider = databricks.created_workspace

  function   = "${var.security_catalog_name}.policies.can_read_okta_group"
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
  policies = {
    abac_demo_okta_group_row_filter = {
      scope = {
        catalog = local.derived_governed_catalogs["abac_demo"].catalog_name
      }
      principals = {
        include = ["okta-databricks-users"]
        exclude = ["giulianoaltobelli@gmail.com"]
      }
      table = {
        key   = "abac_boundary"
        value = "abac_general_access_okta_group"
      }
      columns = {
        first = {
          key   = "protected_column"
          value = "okta_group_names"
          alias = "okta_group_names_value"
        }
      }
      function = "${var.security_catalog_name}.policies.can_read_okta_group"
      comment  = "Filter governed demo rows by the querying user's Okta group membership."
    }
  }
}
