# =============================================================================
# Databricks Governed Unity Catalog Schemas
# =============================================================================

locals {
  governed_schema_config = {
    # salesforce_revenue = {
    #   managed_volumes = {
    #     final = {
    #       model_artifacts = {
    #         name = "model_artifacts"
    #       }
    #     }
    #     uat = {
    #       candidate_assets = {
    #         name = "candidate_assets"
    #       }
    #     }
    #   }
    #
    #   # Placeholder only for future schema-writer rollout:
    #   # uat_writer_principals     = ["00000000-0000-0000-0000-000000000000"]
    #   # release_writer_principals = ["11111111-1111-1111-1111-111111111111"]
    # }
  }

  standard_governed_schema_names = ["raw", "base", "staging", "final", "uat"]

  governed_catalogs_for_schemas = {
    for catalog_key, catalog in local.catalogs :
    catalog_key => catalog
    if catalog.catalog_kind == "governed"
  }

  normalized_governed_schema_config = {
    for catalog_key, catalog in local.governed_catalogs_for_schemas :
    catalog_key => {
      managed_volumes = {
        for schema_name, volumes in try(local.governed_schema_config[catalog_key].managed_volumes, {}) :
        schema_name => {
          for volume_key, volume in volumes :
          volume_key => {
            name    = trimspace(try(volume.name, volume_key))
            comment = try(volume.comment, null)
            owner   = try(volume.owner, null)
            grants  = try(volume.grants, null)
          }
        }
      }
    }
  }

  governed_schemas = {
    for record in flatten([
      for catalog_key, catalog in local.governed_catalogs_for_schemas : [
        for schema_name in local.standard_governed_schema_names : {
          key = "${catalog_key}:${schema_name}"
          value = {
            catalog_name = module.governed_catalogs[catalog_key].catalog_name
            schema_name  = schema_name
            grants = concat(
              [
                {
                  principal  = catalog.catalog_admin_principal
                  privileges = ["ALL_PRIVILEGES"]
                }
              ],
              [
                for principal in catalog.catalog_reader_principals : {
                  principal  = principal
                  privileges = ["USE_SCHEMA"]
                }
              ]
            )
          }
        }
      ]
    ]) : record.key => record.value
  }

  governed_managed_volumes = {
    for record in flatten([
      for catalog_key, catalog in local.governed_catalogs_for_schemas : [
        for schema_name, volumes in local.normalized_governed_schema_config[catalog_key].managed_volumes : [
          for volume_key, volume in volumes : {
            key = "${catalog_key}:${schema_name}:${volume_key}"
            value = {
              name         = trimspace(try(volume.name, volume_key))
              catalog_name = module.governed_catalogs[catalog_key].catalog_name
              schema_name  = schema_name
              volume_type  = "MANAGED"
              comment      = try(volume.comment, null)
              owner        = try(volume.owner, null)
              grants = try(volume.grants, null) != null ? volume.grants : concat(
                [
                  {
                    principal  = catalog.catalog_admin_principal
                    privileges = ["ALL_PRIVILEGES"]
                  }
                ],
                [
                  for principal in catalog.catalog_reader_principals : {
                    principal  = principal
                    privileges = ["READ_VOLUME"]
                  }
                ]
              )
            }
          }
        ]
      ]
    ]) : record.key => record.value
  }

  managed_volume_identity_keys = [
    for volume in values(local.governed_managed_volumes) :
    format(
      "%s.%s.%s",
      lower(trimspace(volume.catalog_name)),
      lower(trimspace(volume.schema_name)),
      lower(trimspace(volume.name))
    )
  ]

  duplicate_managed_volume_identity_keys = toset([
    for key in local.managed_volume_identity_keys : key
    if length([
      for seen in local.managed_volume_identity_keys : seen if seen == key
    ]) > 1
  ])
}

check "governed_schema_config_known_catalog_keys" {
  assert {
    condition = length(setsubtract(
      keys(local.governed_schema_config),
      keys(local.catalogs)
    )) == 0
    error_message = "governed_schema_config keys must already exist in local.catalogs."
  }
}

check "governed_schema_config_governed_catalog_only" {
  assert {
    condition = length(setsubtract(
      keys(local.governed_schema_config),
      keys(local.governed_catalogs_for_schemas)
    )) == 0
    error_message = "governed_schema_config may reference governed catalogs only."
  }
}

check "governed_managed_volume_schema_names" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for schema_name, volumes in catalog.managed_volumes :
        contains(local.standard_governed_schema_names, schema_name)
      ]
    ]))
    error_message = "Managed volumes may be declared only under raw, base, staging, final, or uat."
  }
}

check "governed_managed_volume_override_lists" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) :
          try(volume.grants, null) == null || length(volume.grants) > 0
        ]
      ]
    ]))
    error_message = "Managed-volume grant overrides must be omitted to inherit defaults or set to a non-empty replacement list."
  }
}

check "governed_managed_volume_names" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) :
          trimspace(volume.name) != ""
        ]
      ]
    ]))
    error_message = "Managed-volume declarations must resolve to a non-empty name."
  }
}

check "governed_managed_volume_override_principals" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) : [
            for grant in volume.grants == null ? [] : volume.grants : trimspace(grant.principal) != ""
          ]
        ]
      ]
    ]))
    error_message = "Managed-volume override grant principals must be non-empty."
  }
}

check "governed_managed_volume_override_privilege_lists" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) : [
            for grant in volume.grants == null ? [] : volume.grants : length(grant.privileges) > 0
          ]
        ]
      ]
    ]))
    error_message = "Managed-volume override grants must declare at least one privilege."
  }
}

check "governed_managed_volume_override_privileges" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) : [
            for grant in volume.grants == null ? [] : volume.grants : [
              for privilege in grant.privileges :
              contains(["ALL_PRIVILEGES", "APPLY_TAG", "MANAGE", "READ_VOLUME", "WRITE_VOLUME"], privilege)
            ]
          ]
        ]
      ]
    ]))
    error_message = "Managed-volume override privileges must be one of: ALL_PRIVILEGES, APPLY_TAG, MANAGE, READ_VOLUME, WRITE_VOLUME."
  }
}

check "governed_managed_volume_identities" {
  assert {
    condition     = length(local.duplicate_managed_volume_identity_keys) == 0
    error_message = "Duplicate governed managed-volume identities are not allowed."
  }
}

module "unity_catalog_schemas" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = local.governed_schemas

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
  ]
}

module "unity_catalog_volumes" {
  source = "./modules/databricks_workspace/unity_catalog_volumes"

  providers = {
    databricks = databricks.created_workspace
  }

  volumes = local.governed_managed_volumes

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
    module.unity_catalog_schemas,
  ]
}
