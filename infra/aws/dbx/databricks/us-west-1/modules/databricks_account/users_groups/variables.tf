# Module inputs.
#
# Keep variable descriptions crisp. Prefer `optional(...)` types and defaults where sensible.

variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "workspace_id" {
  description = "Target workspace ID for workspace permission assignments. The `databricks.workspace` provider should point at this workspace."
  type        = string
  default     = ""
}

variable "prevent_destroy" {
  description = "Whether to set lifecycle.prevent_destroy on databricks_user and databricks_group resources."
  type        = bool
  default     = false
}

variable "allow_empty_groups" {
  description = "Whether an empty groups map is allowed when module is enabled."
  type        = bool
  default     = true
}

variable "groups" {
  description = "Account-level groups to create and manage."
  type = map(object({
    display_name          = string
    roles                 = optional(set(string), [])
    workspace_permissions = optional(set(string), [])
    entitlements = optional(object({
      allow_cluster_create       = optional(bool, false)
      allow_instance_pool_create = optional(bool, false)
      databricks_sql_access      = optional(bool, false)
      workspace_access           = optional(bool, false)
      workspace_consume          = optional(bool, false)
    }))
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for permission in coalesce(group.workspace_permissions, toset([])) :
        contains(["ADMIN", "USER"], permission)
      ]
    ]))
    error_message = "groups[*].workspace_permissions may only contain ADMIN or USER."
  }

  validation {
    condition = alltrue([
      for group in values(var.groups) :
      group.entitlements == null ? true : !(
        try(group.entitlements.workspace_consume, false) &&
        (
          try(group.entitlements.workspace_access, false) ||
          try(group.entitlements.databricks_sql_access, false)
        )
      )
    ])
    error_message = "groups[*].entitlements.workspace_consume cannot be true with workspace_access or databricks_sql_access."
  }
}

variable "users" {
  description = "Account-level users to create and manage."
  type = map(object({
    user_name             = string
    display_name          = optional(string)
    active                = optional(bool)
    groups                = optional(set(string), [])
    roles                 = optional(set(string), [])
    workspace_permissions = optional(set(string), [])
    entitlements = optional(object({
      allow_cluster_create       = optional(bool, false)
      allow_instance_pool_create = optional(bool, false)
      databricks_sql_access      = optional(bool, false)
      workspace_access           = optional(bool, false)
      workspace_consume          = optional(bool, false)
    }))
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for user in values(var.users) : [
        for permission in coalesce(user.workspace_permissions, toset([])) :
        contains(["ADMIN", "USER"], permission)
      ]
    ]))
    error_message = "users[*].workspace_permissions may only contain ADMIN or USER."
  }

  validation {
    condition = alltrue([
      for user in values(var.users) :
      user.entitlements == null ? true : !(
        try(user.entitlements.workspace_consume, false) &&
        (
          try(user.entitlements.workspace_access, false) ||
          try(user.entitlements.databricks_sql_access, false)
        )
      )
    ])
    error_message = "users[*].entitlements.workspace_consume cannot be true with workspace_access or databricks_sql_access."
  }
}
