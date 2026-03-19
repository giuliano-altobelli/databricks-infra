# =============================================================================
# Databricks Governed Catalog Creation
# =============================================================================

locals {
  governed_catalog_domains = {
    personal = {
      enabled             = true
      display_name        = "Sandbox Personal"
      catalog_kind        = "personal"
      catalog_name        = "sandbox_personal"
      source              = "personal"
      business_area       = ""
      catalog_admin_group = "platform_admins"
      reader_group        = []
      workspace_ids       = []
    }

    # salesforce_revenue = {
    #   enabled             = true
    #   display_name        = "Sandbox Salesforce Revenue"
    #   catalog_name        = "sandbox_salesforce_revenue"
    #   source              = "salesforce"
    #   business_area       = "revenue"
    #   catalog_type        = "standard_governed"
    #   catalog_admin_group = "platform_admins"
    #   reader_group        = []
    #   managed_volume_overrides = {
    #     final = {
    #       model_artifacts = {
    #         name = "model_artifacts"
    #       }
    #     }
    #   }
    #   # workspace_ids     = ["1234567890123456"] # Optional future shared-metastore visibility
    # }
    # hubspot_shared = {
    #   enabled             = true
    #   display_name        = "Sandbox HubSpot Shared"
    #   catalog_name        = "sandbox_hubspot_shared"
    #   source              = "hubspot"
    #   business_area       = ""
    #   catalog_type        = "standard_governed"
    #   catalog_admin_group = "platform_admins"
    #   reader_group        = []
    # }
    # main = {
    #   enabled             = true
    #   display_name        = "Sandbox Main"
    #   catalog_name        = "sandbox_main"
    #   source              = "main"
    #   business_area       = ""
    #   catalog_type        = "main_empty" # Example schema-less type with schemas = {}
    #   catalog_admin_group = "platform_admins"
    #   reader_group        = []
    # }
  }

  normalized_governed_catalog_domains = {
    for catalog_key, domain in local.governed_catalog_domains :
    catalog_key => {
      enabled                  = try(domain.enabled, true)
      display_name             = trimspace(try(domain.display_name, ""))
      catalog_kind             = trimspace(try(domain.catalog_kind, "governed"))
      catalog_name             = trimspace(try(domain.catalog_name, ""))
      source                   = trimspace(try(domain.source, ""))
      business_area            = trimspace(try(domain.business_area, ""))
      catalog_type             = trimspace(try(domain.catalog_type, ""))
      catalog_admin_group      = trimspace(try(domain.catalog_admin_group, "platform_admins"))
      reader_group             = [for group_key in try(domain.reader_group, []) : trimspace(group_key)]
      managed_volume_overrides = try(domain.managed_volume_overrides, null) == null ? {} : try(domain.managed_volume_overrides, {})
      workspace_ids            = [for workspace_id in try(domain.workspace_ids, []) : trimspace(workspace_id)]
    }
  }

  derived_governed_catalog_names = {
    for catalog_key, domain in local.normalized_governed_catalog_domains :
    catalog_key => domain.catalog_name != "" ? domain.catalog_name : (domain.business_area == "" ? "prod_${domain.source}" : "prod_${domain.source}_${domain.business_area}")
  }

  derived_governed_catalogs = {
    for catalog_key, domain in local.normalized_governed_catalog_domains :
    catalog_key => {
      enabled                 = domain.enabled
      display_name            = domain.display_name != "" ? domain.display_name : local.derived_governed_catalog_names[catalog_key]
      catalog_kind            = domain.catalog_kind == "" ? "governed" : domain.catalog_kind
      catalog_type            = (domain.catalog_kind == "" ? "governed" : domain.catalog_kind) == "governed" ? (domain.catalog_type != "" ? domain.catalog_type : "standard_governed") : ""
      catalog_name            = local.derived_governed_catalog_names[catalog_key]
      aws_safe_catalog_suffix = replace(local.derived_governed_catalog_names[catalog_key], "_", "-")
      catalog_admin_group     = domain.catalog_admin_group
      catalog_admin_principal = try(local.identity_groups[domain.catalog_admin_group].display_name, "")
      reader_group            = domain.reader_group
      catalog_reader_principals = [
        for group_key in domain.reader_group :
        try(local.identity_groups[group_key].display_name, "")
      ]
      managed_volume_overrides = (domain.catalog_kind == "" ? "governed" : domain.catalog_kind) == "governed" ? domain.managed_volume_overrides : {}
      workspace_ids            = domain.workspace_ids
    }
  }

  catalogs = {
    for catalog_key, catalog in local.derived_governed_catalogs :
    catalog_key => catalog
    if catalog.enabled
  }

  governed_catalog_names              = [for catalog in values(local.catalogs) : catalog.catalog_name]
  catalog_aws_safe_suffixes           = [for catalog in values(local.catalogs) : catalog.aws_safe_catalog_suffix]
  duplicate_governed_catalog_names    = length(local.governed_catalog_names) != length(distinct(local.governed_catalog_names))
  duplicate_catalog_aws_safe_suffixes = length(local.catalog_aws_safe_suffixes) != length(distinct(local.catalog_aws_safe_suffixes))
}

check "governed_catalog_sources" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || (domain.source != "" && can(regex("^[a-z0-9_]+$", domain.source)))
    ])
    error_message = "Each governed catalog source must be non-empty lowercase snake_case."
  }
}

check "governed_catalog_business_areas" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || domain.business_area == "" || can(regex("^[a-z0-9_]+$", domain.business_area))
    ])
    error_message = "Each non-empty governed catalog business_area must be lowercase snake_case."
  }
}

check "governed_catalog_admin_groups" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || (domain.catalog_admin_group != "" && contains(keys(local.identity_groups), domain.catalog_admin_group))
    ])
    error_message = "Each enabled governed catalog catalog_admin_group must reference a key defined in local.identity_groups."
  }
}

check "governed_catalog_reader_groups" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || alltrue([
        for group_key in domain.reader_group :
        group_key != "" && contains(keys(local.identity_groups), group_key)
      ])
    ])
    error_message = "Each enabled governed catalog reader_group entry must reference a non-empty key defined in local.identity_groups."
  }
}

check "governed_catalog_reader_groups_unique" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || length(domain.reader_group) == length(distinct(domain.reader_group))
    ])
    error_message = "Each enabled governed catalog reader_group list must contain unique group keys."
  }
}

check "governed_catalog_reader_groups_exclude_admin" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || !contains(domain.reader_group, domain.catalog_admin_group)
    ])
    error_message = "Each enabled governed catalog reader_group list must not include catalog_admin_group."
  }
}

check "governed_catalog_types" {
  assert {
    condition = alltrue([
      for domain in values(local.derived_governed_catalogs) :
      !domain.enabled || domain.catalog_kind != "governed" || contains(keys(local.catalog_types_config), domain.catalog_type)
    ])
    error_message = "Each enabled governed catalog catalog_type must reference a key defined in local.catalog_types_config."
  }
}

check "non_governed_catalog_schema_fields" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      !domain.enabled || (domain.catalog_kind == "" ? "governed" : domain.catalog_kind) == "governed" || (
        domain.catalog_type == "" && length(keys(domain.managed_volume_overrides)) == 0
      )
    ])
    error_message = "Non-governed catalogs must not declare catalog_type or managed_volume_overrides."
  }
}

check "governed_catalog_name_uniqueness" {
  assert {
    condition     = !local.duplicate_governed_catalog_names
    error_message = "Derived governed catalog names must be unique."
  }
}

check "governed_catalog_aws_suffix_uniqueness" {
  assert {
    condition     = !local.duplicate_catalog_aws_safe_suffixes
    error_message = "Derived catalog AWS-safe suffixes must be unique, including the explicit personal catalog."
  }
}

module "governed_catalogs" {
  for_each = local.derived_governed_catalogs
  source   = "./modules/databricks_workspace/unity_catalog_catalog_creation"

  providers = {
    databricks = databricks.created_workspace
  }

  aws_account_id            = var.aws_account_id
  aws_iam_partition         = local.computed_aws_partition
  aws_assume_partition      = local.assume_role_partition
  unity_catalog_iam_arn     = local.unity_catalog_iam_arn
  cmk_admin_arn             = var.cmk_admin_arn == null ? "arn:${local.computed_aws_partition}:iam::${var.aws_account_id}:root" : var.cmk_admin_arn
  resource_prefix           = var.resource_prefix
  workspace_id              = local.workspace_id
  enabled                   = each.value.enabled
  catalog_name              = each.value.catalog_name
  catalog_admin_principal   = each.value.catalog_admin_principal
  catalog_reader_principals = each.value.catalog_reader_principals
  workspace_ids             = each.value.workspace_ids
  set_default_namespace     = false

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    data.databricks_current_metastore.workspace,
    data.databricks_catalogs.workspace,
  ]
}
