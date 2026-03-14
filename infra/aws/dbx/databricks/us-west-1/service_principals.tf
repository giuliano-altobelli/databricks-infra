locals {
  service_principals_enabled = false

  service_principals = {
    uat_promotion = {
      display_name    = "UAT Promotion SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
      entitlements = {
        databricks_sql_access = true
      }
    }

    workspace_agent = {
      display_name    = "Workspace Agent SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_access = true
      }
    }

    # catalog_writer = {
    #   display_name    = "Catalog Writer SP"
    #   principal_scope = "account"
    #   workspace_assignment = {
    #     enabled     = true
    #     permissions = ["USER"]
    #   }
    #   entitlements = {
    #     databricks_sql_access = true
    #   }
    #   unity_catalog_access = {
    #     permission_level = "writer"
    #     catalogs         = "all"
    #   }
    # }
    #
    # reporting_reader = {
    #   display_name    = "Reporting Reader SP"
    #   principal_scope = "workspace"
    #   entitlements = {
    #     workspace_access = true
    #   }
    #   unity_catalog_access = {
    #     permission_level = "reader"
    #     catalogs         = ["salesforce_revenue"]
    #   }
    # }
  }

  service_principals_identity = {
    for principal_key, principal in local.service_principals :
    principal_key => {
      display_name         = principal.display_name
      principal_scope      = principal.principal_scope
      workspace_assignment = try(principal.workspace_assignment, null)
      entitlements         = try(principal.entitlements, null)
    }
  }

  service_principal_unity_catalog_access = !local.service_principals_enabled ? {} : {
    for principal_key, principal in local.service_principals :
    principal_key => {
      principal_scope              = principal.principal_scope
      workspace_assignment_enabled = coalesce(try(principal.workspace_assignment.enabled, null), false)
      permission_level             = lower(trimspace(try(principal.unity_catalog_access.permission_level, "")))
      catalogs_all                 = try(principal.unity_catalog_access.catalogs, null) == "all"
      catalogs_is_string_list = try(principal.unity_catalog_access.catalogs, null) != null && can(tolist(principal.unity_catalog_access.catalogs)) && can([
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
      ])
      explicit_catalog_keys = try(principal.unity_catalog_access.catalogs, null) != null && can(tolist(principal.unity_catalog_access.catalogs)) && can([
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
        ]) ? [
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
      ] : []
    }
    if try(principal.unity_catalog_access, null) != null
  }
}

module "service_principals" {
  source = "./modules/databricks_identity/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  enabled            = local.service_principals_enabled
  workspace_id       = local.workspace_id
  service_principals = local.service_principals_identity

  depends_on = [module.unity_catalog_metastore_assignment]
}

check "service_principal_uc_permission_levels" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      contains(["reader", "writer"], access.permission_level)
    ])
    error_message = "service_principals[*].unity_catalog_access.permission_level must be reader or writer."
  }
}

check "service_principal_uc_catalog_selectors" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || access.catalogs_is_string_list
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs must be \"all\" or a list of catalog keys."
  }
}

check "service_principal_uc_catalog_keys_nonempty" {
  assert {
    condition = alltrue(flatten([
      for access in values(local.service_principal_unity_catalog_access) : [
        for catalog_key in access.catalogs_all ? [] : access.explicit_catalog_keys :
        catalog_key != ""
      ]
    ]))
    error_message = "service_principals[*].unity_catalog_access.catalogs list entries must be non-empty."
  }
}

check "service_principal_uc_catalog_key_lists_nonempty" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || length(access.explicit_catalog_keys) > 0
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs list must contain at least one catalog key."
  }
}

check "service_principal_uc_catalog_keys_unique" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || length(access.explicit_catalog_keys) == length(distinct(access.explicit_catalog_keys))
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs list entries must be unique."
  }
}

check "service_principal_uc_account_scope_workspace_assignment" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.principal_scope != "account" || access.workspace_assignment_enabled
    ])
    error_message = "Account-scoped service principals with unity_catalog_access must enable workspace_assignment."
  }
}
