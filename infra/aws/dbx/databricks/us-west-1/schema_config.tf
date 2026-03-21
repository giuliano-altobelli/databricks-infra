# # =============================================================================
# # Databricks Governed Unity Catalog Schemas
# # =============================================================================

# locals {
#   governed_schema_config = {
#     # Add catalog-specific governed schemas or replace template-derived schema
#     # grants here. This file remains the source of truth for created schemas.
#     # Schema grants are authoritative allow-lists, so excluding a principal
#     # from one schema means replacing that schema's grant list without it.
#     #
#     # salesforce_revenue = {
#     #   # Example: keep the default reader group on base/staging/final/uat, but
#     #   # exclude the Finance Readers group from raw by replacing raw.grants.
#     #   raw = {
#     #     grants = [
#     #       {
#     #         principal  = local.identity_groups.platform_admins.display_name
#     #         privileges = ["ALL_PRIVILEGES"]
#     #       }
#     #       {
#     #         principal  = local.identity_groups.revenue_engineers.display_name
#     #         privileges = ["USE_SCHEMA"]
#     #       }
#     #     ]
#     #   }
#     #
#     #   quarantine = {
#     #     comment = "Catalog-specific governed schema outside the reusable template."
#     #   }
#     # }
#   }

#   normalized_governed_schema_config = {
#     for catalog_key, schemas in local.governed_schema_config :
#     catalog_key => {
#       for raw_schema_name, schema in schemas :
#       trimspace(raw_schema_name) => {
#         comment = try(schema.comment, null)
#         properties = try(schema.properties, null) == null ? null : {
#           for property_key, property_value in schema.properties :
#           trimspace(property_key) => property_value
#         }
#         grants = try(schema.grants, null)
#       }
#     }
#   }

#   normalized_catalog_managed_volume_overrides = {
#     for catalog_key, catalog in local.governed_catalogs_for_schemas :
#     catalog_key => {
#       managed_volumes = {
#         for schema_name, volumes in try(catalog.managed_volume_overrides, {}) :
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

#   effective_governed_schema_config = {
#     for catalog_key, catalog in local.governed_catalogs_for_schemas :
#     catalog_key => {
#       schemas = {
#         for schema_name in distinct(concat(
#           keys(local.governed_catalog_schema_templates[catalog_key].schemas),
#           keys(try(local.normalized_governed_schema_config[catalog_key], {}))
#         )) :
#         schema_name => {
#           comment = try(
#             local.normalized_governed_schema_config[catalog_key][schema_name].comment,
#             try(local.governed_catalog_schema_templates[catalog_key].schemas[schema_name].comment, null)
#           )
#           properties = length(merge(
#             try(local.governed_catalog_schema_templates[catalog_key].schemas[schema_name].properties, {}),
#             try(local.normalized_governed_schema_config[catalog_key][schema_name].properties, {})
#             )) == 0 ? null : merge(
#             try(local.governed_catalog_schema_templates[catalog_key].schemas[schema_name].properties, {}),
#             try(local.normalized_governed_schema_config[catalog_key][schema_name].properties, {})
#           )
#           grants = try(local.normalized_governed_schema_config[catalog_key][schema_name].grants, null)
#         }
#       }

#       managed_volumes = {
#         for schema_name in distinct(concat(
#           keys(try(local.normalized_catalog_types_config[catalog.catalog_type].managed_volumes, {})),
#           keys(local.normalized_catalog_managed_volume_overrides[catalog_key].managed_volumes)
#         )) :
#         schema_name => {
#           for volume_key in distinct(concat(
#             keys(try(local.normalized_catalog_types_config[catalog.catalog_type].managed_volumes[schema_name], {})),
#             keys(try(local.normalized_catalog_managed_volume_overrides[catalog_key].managed_volumes[schema_name], {}))
#           )) :
#           # Matching overrides intentionally replace template attributes rather
#           # than deep-merging list fields such as grants.
#           volume_key => merge(
#             try(local.normalized_catalog_types_config[catalog.catalog_type].managed_volumes[schema_name][volume_key], {}),
#             try(local.normalized_catalog_managed_volume_overrides[catalog_key].managed_volumes[schema_name][volume_key], {})
#           )
#         }
#       }
#     }
#   }

#   governed_schemas = {
#     for record in flatten([
#       for catalog_key, catalog in local.governed_catalogs_for_schemas : [
#         for schema_name, schema in local.effective_governed_schema_config[catalog_key].schemas : {
#           key = "${catalog_key}:${schema_name}"
#           value = {
#             catalog_name = module.governed_catalogs[catalog_key].catalog_name
#             schema_name  = schema_name
#             comment      = try(schema.comment, null)
#             properties   = try(schema.properties, null)
#             grants = try(schema.grants, null) != null ? schema.grants : concat(
#               [
#                 {
#                   principal  = catalog.catalog_admin_principal
#                   privileges = ["ALL_PRIVILEGES"]
#                 }
#               ],
#               [
#                 for principal in catalog.catalog_reader_principals : {
#                   principal  = principal
#                   privileges = ["USE_SCHEMA"]
#                 }
#               ]
#             )
#           }
#         }
#       ]
#     ]) : record.key => record.value
#   }

#   governed_managed_volumes = {
#     for record in flatten([
#       for catalog_key, catalog in local.governed_catalogs_for_schemas : [
#         for schema_name, volumes in local.effective_governed_schema_config[catalog_key].managed_volumes : [
#           for volume_key, volume in volumes : {
#             key = "${catalog_key}:${schema_name}:${volume_key}"
#             value = {
#               name         = trimspace(try(volume.name, volume_key))
#               catalog_name = module.governed_catalogs[catalog_key].catalog_name
#               schema_name  = schema_name
#               volume_type  = "MANAGED"
#               comment      = try(volume.comment, null)
#               owner        = try(volume.owner, null)
#               grants = try(volume.grants, null) != null ? volume.grants : concat(
#                 [
#                   {
#                     principal  = catalog.catalog_admin_principal
#                     privileges = ["ALL_PRIVILEGES"]
#                   }
#                 ],
#                 [
#                   for principal in catalog.catalog_reader_principals : {
#                     principal  = principal
#                     privileges = ["READ_VOLUME"]
#                   }
#                 ]
#               )
#             }
#           }
#         ]
#       ]
#     ]) : record.key => record.value
#   }

#   effective_governed_schema_identities = distinct(flatten([
#     for catalog_key, catalog in local.effective_governed_schema_config : [
#       for schema_name in keys(catalog.schemas) :
#       format(
#         "%s.%s",
#         lower(trimspace(module.governed_catalogs[catalog_key].catalog_name)),
#         lower(trimspace(schema_name))
#       )
#     ]
#   ]))

#   managed_volume_identity_keys = [
#     for volume in values(local.governed_managed_volumes) :
#     format(
#       "%s.%s.%s",
#       lower(trimspace(volume.catalog_name)),
#       lower(trimspace(volume.schema_name)),
#       lower(trimspace(volume.name))
#     )
#   ]

#   duplicate_managed_volume_identity_keys = toset([
#     for key in local.managed_volume_identity_keys : key
#     if length([
#       for seen in local.managed_volume_identity_keys : seen if seen == key
#     ]) > 1
#   ])
# }

# check "governed_schema_names" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for schema_name in keys(catalog.schemas) :
#         schema_name != ""
#       ]
#     ]))
#     error_message = "Governed schema names must resolve to non-empty values."
#   }
# }

# check "governed_schema_property_keys" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for schema in values(catalog.schemas) : [
#           for property_key in try(schema.properties, null) == null ? [] : keys(schema.properties) :
#           trimspace(property_key) != ""
#         ]
#       ]
#     ]))
#     error_message = "Governed schema property keys must be non-empty."
#   }
# }

# check "governed_managed_volume_schema_names" {
#   assert {
#     condition = alltrue([
#       for volume in values(local.governed_managed_volumes) :
#       contains(
#         local.effective_governed_schema_identities,
#         format(
#           "%s.%s",
#           lower(trimspace(volume.catalog_name)),
#           lower(trimspace(volume.schema_name))
#         )
#       )
#     ])
#     error_message = "Managed volumes may be declared only under schemas defined in the effective governed schema configuration."
#   }
# }

# check "governed_managed_volume_grant_lists" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for volumes in values(catalog.managed_volumes) : [
#           for volume in values(volumes) :
#           try(volume.grants, null) == null || length(volume.grants) > 0
#         ]
#       ]
#     ]))
#     error_message = "Managed-volume grants must be omitted to inherit defaults or set to a non-empty replacement list."
#   }
# }

# check "governed_managed_volume_names" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for volumes in values(catalog.managed_volumes) : [
#           for volume in values(volumes) :
#           trimspace(volume.name) != ""
#         ]
#       ]
#     ]))
#     error_message = "Managed-volume declarations must resolve to a non-empty name."
#   }
# }

# check "governed_managed_volume_grant_principals" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for volumes in values(catalog.managed_volumes) : [
#           for volume in values(volumes) : [
#             for grant in volume.grants == null ? [] : volume.grants : trimspace(grant.principal) != ""
#           ]
#         ]
#       ]
#     ]))
#     error_message = "Managed-volume grant principals must be non-empty."
#   }
# }

# check "governed_managed_volume_grant_privilege_lists" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for volumes in values(catalog.managed_volumes) : [
#           for volume in values(volumes) : [
#             for grant in volume.grants == null ? [] : volume.grants : length(grant.privileges) > 0
#           ]
#         ]
#       ]
#     ]))
#     error_message = "Managed-volume grants must declare at least one privilege."
#   }
# }

# check "governed_managed_volume_grant_privileges" {
#   assert {
#     condition = alltrue(flatten([
#       for catalog in values(local.effective_governed_schema_config) : [
#         for volumes in values(catalog.managed_volumes) : [
#           for volume in values(volumes) : [
#             for grant in volume.grants == null ? [] : volume.grants : [
#               for privilege in grant.privileges :
#               contains(["ALL_PRIVILEGES", "APPLY_TAG", "MANAGE", "READ_VOLUME", "WRITE_VOLUME"], privilege)
#             ]
#           ]
#         ]
#       ]
#     ]))
#     error_message = "Managed-volume grant privileges must be one of: ALL_PRIVILEGES, APPLY_TAG, MANAGE, READ_VOLUME, WRITE_VOLUME."
#   }
# }

# check "governed_managed_volume_identities" {
#   assert {
#     condition     = length(local.duplicate_managed_volume_identity_keys) == 0
#     error_message = "Duplicate governed managed-volume identities are not allowed."
#   }
# }

# module "unity_catalog_schemas" {
#   source = "./modules/databricks_workspace/unity_catalog_schemas"

#   providers = {
#     databricks = databricks.created_workspace
#   }

#   schemas = local.governed_schemas

#   depends_on = [
#     module.unity_catalog_metastore_assignment,
#     module.users_groups,
#     module.governed_catalogs,
#   ]
# }

# module "unity_catalog_volumes" {
#   source = "./modules/databricks_workspace/unity_catalog_volumes"

#   providers = {
#     databricks = databricks.created_workspace
#   }

#   volumes = local.governed_managed_volumes

#   depends_on = [
#     module.unity_catalog_metastore_assignment,
#     module.users_groups,
#     module.governed_catalogs,
#     module.unity_catalog_schemas,
#   ]
# }
