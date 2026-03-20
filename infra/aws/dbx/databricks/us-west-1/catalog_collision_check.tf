# data "databricks_current_metastore" "workspace" {
#   provider = databricks.created_workspace

#   provider_config {
#     workspace_id = local.workspace_id
#   }

#   depends_on = [module.unity_catalog_metastore_assignment]
# }

# data "databricks_catalogs" "workspace" {
#   provider = databricks.created_workspace

#   provider_config {
#     workspace_id = local.workspace_id
#   }

#   depends_on = [module.unity_catalog_metastore_assignment]
# }

# locals {
#   metastore_catalog_names  = toset(data.databricks_catalogs.workspace.ids)
#   configured_catalog_names = toset([for catalog in values(local.catalogs) : catalog.catalog_name])
#   colliding_catalog_names  = sort(tolist(setintersection(local.metastore_catalog_names, local.configured_catalog_names)))
# }

# check "sandbox_catalog_name_collisions" {
#   assert {
#     condition     = length(local.colliding_catalog_names) == 0
#     error_message = "Configured sandbox catalogs already exist in metastore ${try(data.databricks_current_metastore.workspace.metastore_info[0].metastore_id, data.databricks_current_metastore.workspace.id)}: ${join(", ", local.colliding_catalog_names)}. The sandbox branch creates new catalogs only; rename or remove the existing catalogs before re-running. Existing catalogs are not adopted into Terraform state in this branch."
#   }
# }
