variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "workspace_id" {
  description = "Target workspace ID for account-scoped workspace assignment. The databricks.workspace provider must point at this same workspace when entitlements are managed."
  type        = string
  default     = ""
}

variable "service_principals" {
  description = "Databricks service principals keyed by stable caller-defined identifiers."
  type = map(object({
    display_name    = string
    principal_scope = string
    workspace_assignment = optional(object({
      enabled     = optional(bool, false)
      permissions = optional(set(string), ["USER"])
    }))
    entitlements = optional(object({
      allow_cluster_create       = optional(bool)
      allow_instance_pool_create = optional(bool)
      databricks_sql_access      = optional(bool)
      workspace_access           = optional(bool)
      workspace_consume          = optional(bool)
    }))
  }))
  default = {}

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      contains(["account", "workspace"], principal.principal_scope)
    ])
    error_message = "service_principals[*].principal_scope must be either account or workspace."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for principal in values(var.service_principals) : [
        for permission in coalesce(try(principal.workspace_assignment.permissions, null), toset([])) :
        contains(["ADMIN", "USER"], permission)
      ]
    ]))
    error_message = "service_principals[*].workspace_assignment.permissions may only contain ADMIN or USER."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      !coalesce(try(principal.workspace_assignment.enabled, null), false) ||
      length(coalesce(try(principal.workspace_assignment.permissions, null), toset(["USER"]))) > 0
    ])
    error_message = "service_principals[*].workspace_assignment.permissions must be non-empty when workspace_assignment.enabled is true."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.entitlements == null ? true : !(
        coalesce(try(principal.entitlements.workspace_consume, null), false) &&
        (
          coalesce(try(principal.entitlements.workspace_access, null), false) ||
          coalesce(try(principal.entitlements.databricks_sql_access, null), false)
        )
      )
    ])
    error_message = "service_principals[*].entitlements.workspace_consume cannot be true with workspace_access or databricks_sql_access."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.principal_scope != "workspace" || !coalesce(try(principal.workspace_assignment.enabled, null), false)
    ])
    error_message = "Workspace-scoped service principals must not request workspace assignment."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.principal_scope != "account" || principal.entitlements == null || coalesce(try(principal.workspace_assignment.enabled, null), false)
    ])
    error_message = "Account-scoped service principals may manage entitlements only when workspace_assignment.enabled is true."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      !coalesce(try(principal.workspace_assignment.enabled, null), false) || trimspace(var.workspace_id) != ""
    ])
    error_message = "workspace_id must be non-empty when any service principal requests workspace assignment."
  }
}
