output "user_ids" {
  description = "Map of user keys to Databricks user IDs."
  value       = local.user_id_map

  precondition {
    condition     = !var.enabled || trimspace(var.workspace_id) != ""
    error_message = "workspace_id must be non-empty when enabled is true."
  }

  precondition {
    condition     = !var.enabled || var.allow_empty_groups || length(var.groups) > 0
    error_message = "groups must be non-empty when enabled is true and allow_empty_groups is false."
  }

  precondition {
    condition     = !var.enabled || length(local.invalid_group_references) == 0
    error_message = "users[*].groups contains missing group keys: ${join(", ", local.invalid_group_references)}."
  }
}

output "group_ids" {
  description = "Map of group keys to Databricks group IDs."
  value       = local.group_id_map
}

output "membership_ids" {
  description = "Map of membership keys to Databricks group membership IDs."
  value       = { for membership_key, membership in databricks_group_member.memberships : membership_key => membership.id }
}

output "membership_keys" {
  description = "Set of membership keys in user:<user_key>:<group_key> format."
  value       = toset(keys(databricks_group_member.memberships))
}

output "user_role_ids" {
  description = "Map of user role keys to Databricks user role IDs."
  value       = { for role_key, role in databricks_user_role.user_roles : role_key => role.id }
}

output "group_role_ids" {
  description = "Map of group role keys to Databricks group role IDs."
  value       = { for role_key, role in databricks_group_role.group_roles : role_key => role.id }
}

output "workspace_assignment_ids" {
  description = "Map of workspace assignment IDs keyed by user:<user_key> or group:<group_key>."
  value = merge(
    { for user_key, assignment in databricks_mws_permission_assignment.user_workspace_assignments : "user:${user_key}" => assignment.id },
    { for group_key, assignment in databricks_mws_permission_assignment.group_workspace_assignments : "group:${group_key}" => assignment.id }
  )
}

output "entitlements_ids" {
  description = "Map of entitlement IDs keyed by user:<user_key> or group:<group_key>."
  value = merge(
    { for user_key, entitlement in databricks_entitlements.user_entitlements : "user:${user_key}" => entitlement.id },
    { for group_key, entitlement in databricks_entitlements.group_entitlements : "group:${group_key}" => entitlement.id }
  )
}
