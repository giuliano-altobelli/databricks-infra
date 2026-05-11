# =============================================================================
# Databricks Governed Unity Catalog Table Permissions
# =============================================================================

locals {
  table_permissions_config = {
    # Add table-specific reader allowlists here after the governed catalog and
    # schema root path is active. These grants are authoritative per table.
    # schema_name may target any effective governed schema, including uat.
    #
    # salesforce_revenue_raw_transactions = {
    #   catalog_key       = "salesforce_revenue"
    #   schema_name       = "raw"
    #   table_name        = "transactions"
    #   reader_group_keys = ["revenue_readers"]
    # }
  }
}

# Uncomment this derived block with the governed catalog/schema root path.
# locals {
#   normalized_table_permissions_config = {
#     for table_key, table in local.table_permissions_config :
#     table_key => {
#       catalog_key       = trimspace(table.catalog_key)
#       schema_name       = trimspace(table.schema_name)
#       table_name        = trimspace(table.table_name)
#       reader_group_keys = [for group_key in table.reader_group_keys : trimspace(group_key)]
#     }
#   }

#   unity_catalog_table_permissions = {
#     for table_key, table in local.normalized_table_permissions_config :
#     table_key => {
#       catalog_name = module.governed_catalogs[table.catalog_key].catalog_name
#       schema_name  = table.schema_name
#       table_name   = table.table_name
#       reader_principals = [
#         for group_key in table.reader_group_keys :
#         local.identity_groups[group_key].display_name
#       ]
#     }
#   }
# }

# check "table_permission_catalog_keys" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       table.catalog_key != "" && contains(keys(local.catalogs), table.catalog_key)
#     ])
#     error_message = "Each table permission catalog_key must reference an enabled key defined in local.catalogs."
#   }
# }

# check "table_permission_schema_names" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       table.schema_name != "" && try(
#         contains(keys(local.effective_governed_schema_config[table.catalog_key].schemas), table.schema_name),
#         false
#       )
#     ])
#     error_message = "Each table permission schema_name must reference an effective governed schema for its catalog_key."
#   }
# }

# check "table_permission_table_names" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       table.table_name != ""
#     ])
#     error_message = "Each table permission table_name must be non-empty."
#   }
# }

# check "table_permission_reader_group_keys" {
#   assert {
#     condition = alltrue(flatten([
#       for table in values(local.normalized_table_permissions_config) : [
#         for group_key in table.reader_group_keys :
#         group_key != "" && contains(keys(local.identity_groups), group_key)
#       ]
#     ]))
#     error_message = "Each table permission reader_group_keys entry must reference a non-empty key defined in local.identity_groups."
#   }
# }

# check "table_permission_reader_group_keys_nonempty" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       length(table.reader_group_keys) > 0
#     ])
#     error_message = "Each table permission must declare at least one reader_group_keys entry."
#   }
# }

# check "table_permission_reader_group_keys_exclude_admin" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       try(!contains(table.reader_group_keys, local.catalogs[table.catalog_key].catalog_admin_group), false)
#     ])
#     error_message = "Table permission reader_group_keys must not include the referenced catalog catalog_admin_group."
#   }
# }

# check "table_permission_reader_group_keys_subset" {
#   assert {
#     condition = alltrue([
#       for table in values(local.normalized_table_permissions_config) :
#       try(alltrue([
#         for group_key in table.reader_group_keys :
#         contains(local.catalogs[table.catalog_key].reader_group, group_key)
#       ]), false)
#     ])
#     error_message = "Table permission reader_group_keys must be a subset of the referenced catalog reader_group list."
#   }
# }

# module "unity_catalog_table_permissions" {
#   source = "./modules/databricks_workspace/unity_catalog_table_permissions"

#   providers = {
#     databricks = databricks.created_workspace
#   }

#   tables = local.unity_catalog_table_permissions

#   depends_on = [
#     module.unity_catalog_metastore_assignment,
#     module.users_groups,
#     module.governed_catalogs,
#     module.unity_catalog_schemas,
#   ]
# }
