locals {
  enabled_service_principals = var.enabled ? var.service_principals : {}

  account_service_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => principal
    if principal.principal_scope == "account"
  }

  workspace_service_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => principal
    if principal.principal_scope == "workspace"
  }

  workspace_assignments = {
    for principal_key, principal in local.account_service_principals :
    principal_key => sort(tolist(coalesce(try(principal.workspace_assignment.permissions, null), toset(["USER"]))))
    if coalesce(try(principal.workspace_assignment.enabled, null), false)
  }

  entitlement_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => {
      allow_cluster_create       = coalesce(try(principal.entitlements.allow_cluster_create, null), false)
      allow_instance_pool_create = coalesce(try(principal.entitlements.allow_instance_pool_create, null), false)
      databricks_sql_access      = coalesce(try(principal.entitlements.databricks_sql_access, null), false)
      workspace_access           = coalesce(try(principal.entitlements.workspace_access, null), false)
      workspace_consume          = coalesce(try(principal.entitlements.workspace_consume, null), false) ? true : null
    }
    if principal.entitlements != null
  }
}

resource "databricks_service_principal" "account" {
  provider = databricks.mws
  for_each = local.account_service_principals

  display_name = each.value.display_name
}

resource "databricks_service_principal" "workspace" {
  provider = databricks.workspace
  for_each = local.workspace_service_principals

  display_name = each.value.display_name
}

locals {
  service_principal_ids = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.id },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.id }
  )

  service_principal_application_ids = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.application_id },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.application_id }
  )

  service_principal_display_names = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.display_name },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.display_name }
  )
}

resource "databricks_mws_permission_assignment" "workspace" {
  provider = databricks.mws
  for_each = local.workspace_assignments

  workspace_id = var.workspace_id
  principal_id = local.service_principal_ids[each.key]
  permissions  = each.value
}

resource "databricks_entitlements" "workspace" {
  provider = databricks.workspace
  for_each = local.entitlement_principals

  service_principal_id       = local.service_principal_ids[each.key]
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
  databricks_sql_access      = each.value.databricks_sql_access
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume

  depends_on = [databricks_mws_permission_assignment.workspace]
}
