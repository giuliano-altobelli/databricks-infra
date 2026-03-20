# # =============================================================================
# # Databricks Governed Catalog Schema Templates
# # =============================================================================

# locals {
#   governed_catalogs_for_schemas = {
#     for catalog_key, catalog in local.catalogs :
#     catalog_key => catalog
#     if catalog.catalog_kind == "governed"
#   }

#   catalog_type_schema_entries = flatten([
#     for catalog_type_key, catalog_type in local.catalog_types_config : [
#       for raw_schema_name, schema in try(catalog_type.schemas, {}) : {
#         catalog_type_key = catalog_type_key
#         schema_name      = trimspace(raw_schema_name)
#         comment          = try(schema.comment, null)
#         properties       = try(schema.properties, null)
#       }
#     ]
#   ])

#   normalized_catalog_types_config = {
#     for catalog_type_key, catalog_type in local.catalog_types_config :
#     catalog_type_key => {
#       schemas = {
#         for raw_schema_name, schema in try(catalog_type.schemas, {}) :
#         trimspace(raw_schema_name) => {
#           comment = try(schema.comment, null)
#           properties = try(schema.properties, null) == null ? null : {
#             for property_key, property_value in schema.properties :
#             trimspace(property_key) => property_value
#           }
#         }
#       }

#       managed_volumes = {
#         for schema_name, volumes in try(catalog_type.managed_volumes, {}) :
#         trimspace(schema_name) => {
#           for volume_key, volume in volumes :
#           volume_key => {
#             name    = trimspace(try(volume.name, volume_key))
#             comment = try(volume.comment, null)
#             owner   = try(volume.owner, null)
#             grants  = try(volume.grants, null)
#           }
#         }
#       }
#     }
#   }

#   catalog_type_managed_volume_schema_entries = flatten([
#     for catalog_type_key, catalog_type in local.normalized_catalog_types_config : [
#       for schema_name, volumes in catalog_type.managed_volumes : {
#         catalog_type_key = catalog_type_key
#         schema_name      = schema_name
#       }
#     ]
#   ])

#   invalid_catalog_type_managed_volume_schema_keys = sort([
#     for entry in local.catalog_type_managed_volume_schema_entries :
#     format("%s.%s", entry.catalog_type_key, entry.schema_name)
#     if entry.schema_name == "" || !contains(
#       keys(local.normalized_catalog_types_config[entry.catalog_type_key].schemas),
#       entry.schema_name
#     )
#   ])

#   catalog_type_schema_identity_keys = [
#     for entry in local.catalog_type_schema_entries :
#     format("%s.%s", lower(entry.catalog_type_key), lower(entry.schema_name))
#   ]

#   duplicate_catalog_type_schema_identity_keys = toset([
#     for key in local.catalog_type_schema_identity_keys : key
#     if length([
#       for seen in local.catalog_type_schema_identity_keys : seen if seen == key
#     ]) > 1
#   ])

#   governed_catalog_schema_templates = {
#     for catalog_key, catalog in local.governed_catalogs_for_schemas :
#     catalog_key => {
#       catalog_type = catalog.catalog_type
#       schemas      = try(local.normalized_catalog_types_config[catalog.catalog_type].schemas, {})
#     }
#   }
# }

# check "catalog_type_schema_names" {
#   assert {
#     condition = alltrue([
#       for entry in local.catalog_type_schema_entries :
#       entry.schema_name != ""
#     ])
#     error_message = "Catalog type schema keys must resolve to non-empty schema names."
#   }
# }

# check "catalog_type_schema_property_keys" {
#   assert {
#     condition = alltrue(flatten([
#       for entry in local.catalog_type_schema_entries : [
#         for property_key in entry.properties == null ? [] : keys(entry.properties) :
#         trimspace(property_key) != ""
#       ]
#     ]))
#     error_message = "Catalog type schema property keys must be non-empty."
#   }
# }

# check "catalog_type_schema_identities" {
#   assert {
#     condition     = length(local.duplicate_catalog_type_schema_identity_keys) == 0
#     error_message = "Duplicate catalog type schema identities are not allowed after normalization."
#   }
# }
