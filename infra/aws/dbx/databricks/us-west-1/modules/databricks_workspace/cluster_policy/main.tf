locals {
  enabled_policies = var.enabled ? var.cluster_policies : {}

  normalized_permissions = {
    for policy_key, policy in local.enabled_policies : policy_key => [
      for grant in policy.permissions : {
        principal_type   = grant.principal_type
        principal_name   = grant.principal_name
        permission_level = coalesce(try(grant.permission_level, null), "CAN_USE")
      }
    ]
  }

  flattened_permissions = flatten([
    for policy_key, permissions in local.normalized_permissions : [
      for grant in permissions : merge(grant, {
        policy_key = policy_key
      })
    ]
  ])

  permission_key_list = [
    for grant in local.flattened_permissions :
    "${grant.policy_key}:${grant.principal_type}:${grant.principal_name}:${grant.permission_level}"
  ]

  duplicate_permission_keys = toset([
    for key in local.permission_key_list : key
    if length([
      for seen in local.permission_key_list : seen if seen == key
    ]) > 1
  ])
}

resource "databricks_cluster_policy" "this" {
  for_each = local.enabled_policies

  name        = each.value.name
  description = try(each.value.description, null)
  definition  = each.value.definition
}

resource "databricks_permissions" "cluster_policy" {
  for_each = local.enabled_policies

  cluster_policy_id = databricks_cluster_policy.this[each.key].id

  dynamic "access_control" {
    for_each = local.normalized_permissions[each.key]

    content {
      permission_level       = access_control.value.permission_level
      group_name             = access_control.value.principal_type == "group" ? access_control.value.principal_name : null
      user_name              = access_control.value.principal_type == "user" ? access_control.value.principal_name : null
      service_principal_name = access_control.value.principal_type == "service_principal" ? access_control.value.principal_name : null
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_permission_keys) == 0
      error_message = "Duplicate cluster policy permission tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_permission_keys)))}"
    }
  }
}
