locals {
  enabled_users  = var.enabled ? var.users : {}
  enabled_groups = var.enabled ? var.groups : {}

  referenced_group_keys = toset(flatten([
    for user in values(var.users) : tolist(coalesce(user.groups, toset([])))
  ]))
  invalid_group_references = sort(tolist(setsubtract(local.referenced_group_keys, toset(keys(var.groups)))))

  memberships = {
    for membership in flatten([
      for user_key, user in local.enabled_users : [
        for group_key in sort(tolist(coalesce(user.groups, toset([])))) : {
          key       = "user:${user_key}:${group_key}"
          user_key  = user_key
          group_key = group_key
        }
        if contains(keys(local.enabled_groups), group_key)
      ]
    ]) : membership.key => membership
  }

  user_roles = {
    for user_role in flatten([
      for user_key, user in local.enabled_users : [
        for role in sort(tolist(coalesce(user.roles, toset([])))) : {
          key      = "${user_key}:${role}"
          user_key = user_key
          role     = role
        }
      ]
    ]) : user_role.key => user_role
  }

  group_roles = {
    for group_role in flatten([
      for group_key, group in local.enabled_groups : [
        for role in sort(tolist(coalesce(group.roles, toset([])))) : {
          key       = "${group_key}:${role}"
          group_key = group_key
          role      = role
        }
      ]
    ]) : group_role.key => group_role
  }

  user_workspace_assignments = {
    for user_key, user in local.enabled_users :
    user_key => sort(tolist(coalesce(user.workspace_permissions, toset([]))))
    if length(coalesce(user.workspace_permissions, toset([]))) > 0
  }

  group_workspace_assignments = {
    for group_key, group in local.enabled_groups :
    group_key => sort(tolist(coalesce(group.workspace_permissions, toset([]))))
    if length(coalesce(group.workspace_permissions, toset([]))) > 0
  }

  user_entitlements = {
    for user_key, user in local.enabled_users :
    user_key => user.entitlements
    if user.entitlements != null
  }

  group_entitlements = {
    for group_key, group in local.enabled_groups :
    group_key => group.entitlements
    if group.entitlements != null
  }
}

resource "databricks_user" "users" {
  provider = databricks.mws
  for_each = var.prevent_destroy ? {} : local.enabled_users

  user_name    = each.value.user_name
  display_name = each.value.display_name
  active       = each.value.active
}

resource "databricks_user" "users_protected" {
  provider = databricks.mws
  for_each = var.prevent_destroy ? local.enabled_users : {}

  user_name    = each.value.user_name
  display_name = each.value.display_name
  active       = each.value.active

  lifecycle {
    prevent_destroy = true
  }
}

resource "databricks_group" "groups" {
  provider = databricks.mws
  for_each = var.prevent_destroy ? {} : local.enabled_groups

  display_name = each.value.display_name
}

resource "databricks_group" "groups_protected" {
  provider = databricks.mws
  for_each = var.prevent_destroy ? local.enabled_groups : {}

  display_name = each.value.display_name

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  user_id_map = merge(
    { for user_key, user in databricks_user.users : user_key => user.id },
    { for user_key, user in databricks_user.users_protected : user_key => user.id }
  )
  group_id_map = merge(
    { for group_key, group in databricks_group.groups : group_key => group.id },
    { for group_key, group in databricks_group.groups_protected : group_key => group.id }
  )
}

resource "databricks_group_member" "memberships" {
  provider = databricks.mws
  for_each = local.memberships

  group_id  = local.group_id_map[each.value.group_key]
  member_id = local.user_id_map[each.value.user_key]
}

resource "databricks_user_role" "user_roles" {
  provider = databricks.mws
  for_each = local.user_roles

  user_id = local.user_id_map[each.value.user_key]
  role    = each.value.role
}

resource "databricks_group_role" "group_roles" {
  provider = databricks.mws
  for_each = local.group_roles

  group_id = local.group_id_map[each.value.group_key]
  role     = each.value.role
}

resource "databricks_mws_permission_assignment" "user_workspace_assignments" {
  provider = databricks.mws
  for_each = local.user_workspace_assignments

  workspace_id = var.workspace_id
  principal_id = local.user_id_map[each.key]
  permissions  = each.value
}

resource "databricks_mws_permission_assignment" "group_workspace_assignments" {
  provider = databricks.mws
  for_each = local.group_workspace_assignments

  workspace_id = var.workspace_id
  principal_id = local.group_id_map[each.key]
  permissions  = each.value
}

resource "databricks_entitlements" "user_entitlements" {
  provider = databricks.workspace
  for_each = local.user_entitlements

  user_id                    = local.user_id_map[each.key]
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
  databricks_sql_access      = each.value.databricks_sql_access
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume
}

resource "databricks_entitlements" "group_entitlements" {
  provider = databricks.workspace
  for_each = local.group_entitlements

  group_id                   = local.group_id_map[each.key]
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
  databricks_sql_access      = each.value.databricks_sql_access
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume
}
