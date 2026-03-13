# =============================================================================
# Databricks Governed Catalog Creation
# =============================================================================

locals {
  governed_catalog_domains = {
    personal = {
      catalog_kind  = "personal"
      catalog_name  = "personal"
      source        = "personal"
      business_area = ""
      workspace_ids = []
    }

    # salesforce_revenue = {
    #   source        = "salesforce"
    #   business_area = "revenue"
    #   # workspace_ids = ["1234567890123456"] # Optional future shared-metastore visibility
    # }
    # hubspot_shared = {
    #   source        = "hubspot"
    #   business_area = ""
    # }
  }

  normalized_governed_catalog_domains = {
    for catalog_key, domain in local.governed_catalog_domains :
    catalog_key => {
      catalog_kind  = trimspace(try(domain.catalog_kind, "governed"))
      catalog_name  = trimspace(try(domain.catalog_name, ""))
      source        = trimspace(domain.source)
      business_area = trimspace(try(domain.business_area, ""))
      workspace_ids = [for workspace_id in try(domain.workspace_ids, []) : trimspace(workspace_id)]
    }
  }

  governed_catalogs_enabled = length(local.normalized_governed_catalog_domains) > 0

  derived_governed_catalogs = local.governed_catalogs_enabled ? {
    for catalog_key, domain in local.normalized_governed_catalog_domains :
    catalog_key => {
      catalog_kind            = domain.catalog_kind == "" ? "governed" : domain.catalog_kind
      catalog_name            = domain.catalog_name != "" ? domain.catalog_name : (domain.business_area == "" ? "prod_${domain.source}" : "prod_${domain.source}_${domain.business_area}")
      aws_safe_catalog_suffix = replace(domain.catalog_name != "" ? domain.catalog_name : (domain.business_area == "" ? "prod_${domain.source}" : "prod_${domain.source}_${domain.business_area}"), "_", "-")
      workspace_ids           = domain.workspace_ids
    }
  } : {}

  catalogs = local.derived_governed_catalogs

  governed_catalog_names              = [for catalog in values(local.derived_governed_catalogs) : catalog.catalog_name]
  catalog_names                       = [for catalog in values(local.catalogs) : catalog.catalog_name]
  catalog_aws_safe_suffixes           = [for catalog in values(local.catalogs) : catalog.aws_safe_catalog_suffix]
  legacy_isolated_catalog_name        = replace("${var.resource_prefix}-catalog-${local.workspace_id}", "-", "_")
  duplicate_governed_catalog_names    = length(local.governed_catalog_names) != length(distinct(local.governed_catalog_names))
  duplicate_catalog_aws_safe_suffixes = length(local.catalog_aws_safe_suffixes) != length(distinct(local.catalog_aws_safe_suffixes))
}

check "governed_catalog_sources" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      domain.source != "" && can(regex("^[a-z0-9_]+$", domain.source))
    ])
    error_message = "Each governed catalog source must be non-empty lowercase snake_case."
  }
}

check "governed_catalog_business_areas" {
  assert {
    condition = alltrue([
      for domain in values(local.normalized_governed_catalog_domains) :
      domain.business_area == "" || can(regex("^[a-z0-9_]+$", domain.business_area))
    ])
    error_message = "Each non-empty governed catalog business_area must be lowercase snake_case."
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

check "governed_catalog_existing_catalog_overlap" {
  assert {
    condition     = local.effective_uc_catalog_mode != "existing" || !contains(local.catalog_names, var.uc_existing_catalog_name)
    error_message = "The governed catalog set must not overlap with var.uc_existing_catalog_name."
  }
}

# In create-workspace flows the legacy isolated catalog name can remain unknown
# until apply because workspace_id is created by Terraform in the same run.
check "governed_catalog_legacy_isolated_overlap" {
  assert {
    condition     = local.effective_uc_catalog_mode != "isolated" || local.create_workspace || !contains(local.catalog_names, local.legacy_isolated_catalog_name)
    error_message = "The governed catalog set must not overlap with the legacy isolated catalog name in existing-workspace flows."
  }
}

module "governed_catalogs" {
  for_each = local.catalogs
  source   = "./modules/databricks_workspace/unity_catalog_catalog_creation"

  providers = {
    databricks = databricks.created_workspace
  }

  aws_account_id          = var.aws_account_id
  aws_iam_partition       = local.computed_aws_partition
  aws_assume_partition    = local.assume_role_partition
  unity_catalog_iam_arn   = local.unity_catalog_iam_arn
  cmk_admin_arn           = var.cmk_admin_arn == null ? "arn:${local.computed_aws_partition}:iam::${var.aws_account_id}:root" : var.cmk_admin_arn
  resource_prefix         = var.resource_prefix
  workspace_id            = local.workspace_id
  catalog_name            = each.value.catalog_name
  catalog_admin_principal = local.identity_groups.platform_admins.display_name
  workspace_ids           = each.value.workspace_ids
  set_default_namespace   = false

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
  ]
}
