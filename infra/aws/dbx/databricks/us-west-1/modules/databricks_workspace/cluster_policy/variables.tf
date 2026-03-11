variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "cluster_policies" {
  description = "Cluster policies keyed by stable caller-defined identifiers."
  type = map(object({
    name        = string
    definition  = string
    description = optional(string)
    permissions = list(object({
      principal_type   = string
      principal_name   = string
      permission_level = optional(string, "CAN_USE")
    }))
  }))

  validation {
    condition = alltrue([
      for policy in values(var.cluster_policies) : can(jsondecode(policy.definition))
    ])
    error_message = "Each cluster policy definition must be valid JSON."
  }

  validation {
    condition = alltrue([
      for policy in values(var.cluster_policies) : length(policy.permissions) > 0
    ])
    error_message = "Each cluster policy must declare at least one permission entry."
  }

  validation {
    condition = alltrue(flatten([
      for policy in values(var.cluster_policies) : [
        for grant in policy.permissions : contains(["group", "user", "service_principal"], grant.principal_type)
      ]
    ]))
    error_message = "Each permission principal_type must be one of: group, user, service_principal."
  }

  validation {
    condition = alltrue(flatten([
      for policy in values(var.cluster_policies) : [
        for grant in policy.permissions : coalesce(try(grant.permission_level, null), "CAN_USE") == "CAN_USE"
      ]
    ]))
    error_message = "Each permission permission_level must be CAN_USE."
  }
}
