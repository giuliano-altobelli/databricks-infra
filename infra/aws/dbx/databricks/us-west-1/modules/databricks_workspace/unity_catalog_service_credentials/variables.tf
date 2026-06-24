variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "current_workspace_id" {
  description = "Current workspace ID used to seed isolated workspace bindings."
  type        = string
  default     = ""

  validation {
    condition     = !var.enabled || (trimspace(var.current_workspace_id) != "" && can(tonumber(var.current_workspace_id)))
    error_message = "current_workspace_id must be a non-empty numeric string when enabled is true."
  }
}

variable "service_credentials" {
  description = "Unity Catalog service credentials keyed by stable caller-defined identifiers."
  type = map(object({
    name    = string
    comment = optional(string)
    owner   = optional(string)
    aws = object({
      role_arn = string
    })
    skip_validation       = optional(bool, false)
    force_destroy         = optional(bool, false)
    force_update          = optional(bool, false)
    workspace_access_mode = optional(string, "ISOLATION_MODE_ISOLATED")
    workspace_ids         = optional(list(string), [])
    grants = optional(list(object({
      principal  = string
      privileges = optional(list(string), ["ACCESS"])
    })), [])
  }))
  default = {}

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.service_credentials) :
      trimspace(credential.name) != ""
    ])
    error_message = "Each service credential name must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.service_credentials) :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/.+", credential.aws.role_arn))
    ])
    error_message = "Each service credential aws.role_arn must be a valid AWS IAM role ARN."
  }

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.service_credentials) :
      contains(["ISOLATION_MODE_ISOLATED", "ISOLATION_MODE_OPEN"], credential.workspace_access_mode)
    ])
    error_message = "Each service credential workspace_access_mode must be ISOLATION_MODE_ISOLATED or ISOLATION_MODE_OPEN."
  }

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.service_credentials) :
      credential.workspace_access_mode != "ISOLATION_MODE_OPEN" || length(credential.workspace_ids) == 0
    ])
    error_message = "Service credentials with workspace_access_mode = ISOLATION_MODE_OPEN must not declare workspace_ids."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.service_credentials) : [
        for workspace_id in credential.workspace_ids :
        trimspace(workspace_id) != "" && can(tonumber(workspace_id))
      ]
    ]))
    error_message = "Service credential workspace_ids must be non-empty numeric strings."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.service_credentials) : [
        for grant in credential.grants : trimspace(grant.principal) != ""
      ]
    ]))
    error_message = "Each service credential grant principal must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.service_credentials) : [
        for grant in credential.grants : length(grant.privileges) > 0
      ]
    ]))
    error_message = "Each service credential grant must declare at least one privilege."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.service_credentials) : [
        for grant in credential.grants : [
          for privilege in grant.privileges :
          privilege == "ACCESS"
        ]
      ]
    ]))
    error_message = "Service credential grant privileges must be ACCESS in this phase."
  }
}
