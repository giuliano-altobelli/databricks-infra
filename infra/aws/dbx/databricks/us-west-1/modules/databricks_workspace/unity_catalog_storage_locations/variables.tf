variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "current_workspace_id" {
  description = "Current workspace ID used to seed isolated workspace bindings."
  type        = string

  validation {
    condition     = !var.enabled || trimspace(var.current_workspace_id) != ""
    error_message = "current_workspace_id must be non-empty when enabled is true."
  }

  validation {
    condition     = !var.enabled || can(tonumber(var.current_workspace_id))
    error_message = "current_workspace_id must be numeric when enabled is true."
  }
}

variable "storage_credentials" {
  description = "Unity Catalog storage credentials keyed by stable caller-defined identifiers."
  type = map(object({
    name                  = string
    role_arn              = string
    comment               = optional(string)
    owner                 = optional(string)
    read_only             = optional(bool, false)
    skip_validation       = optional(bool, false)
    force_destroy         = optional(bool, false)
    force_update          = optional(bool, false)
    workspace_access_mode = optional(string, "ISOLATION_MODE_ISOLATED")
    workspace_ids         = optional(list(string), [])
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.storage_credentials) :
      contains(["ISOLATION_MODE_ISOLATED", "ISOLATION_MODE_OPEN"], credential.workspace_access_mode)
    ])
    error_message = "Each storage credential workspace_access_mode must be ISOLATION_MODE_ISOLATED or ISOLATION_MODE_OPEN."
  }

  validation {
    condition = !var.enabled || alltrue([
      for credential in values(var.storage_credentials) :
      credential.workspace_access_mode != "ISOLATION_MODE_OPEN" || length(credential.workspace_ids) == 0
    ])
    error_message = "Storage credentials with workspace_access_mode = ISOLATION_MODE_OPEN must not declare workspace_ids."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.storage_credentials) : [
        for workspace_id in credential.workspace_ids :
        trimspace(workspace_id) != "" && can(tonumber(workspace_id))
      ]
    ]))
    error_message = "Storage credential workspace_ids must be non-empty numeric strings."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.storage_credentials) : [
        for grant in credential.grants : length(grant.privileges) > 0
      ]
    ]))
    error_message = "Each storage credential grant must declare at least one privilege."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for credential in values(var.storage_credentials) : [
        for grant in credential.grants : [
          for privilege in grant.privileges :
          contains([
            "ALL_PRIVILEGES",
            "CREATE_EXTERNAL_LOCATION",
            "CREATE_EXTERNAL_TABLE",
            "MANAGE",
            "READ_FILES",
            "WRITE_FILES"
          ], privilege)
        ]
      ]
    ]))
    error_message = "Storage credential grant privileges must be one of: ALL_PRIVILEGES, CREATE_EXTERNAL_LOCATION, CREATE_EXTERNAL_TABLE, MANAGE, READ_FILES, WRITE_FILES."
  }
}

variable "external_locations" {
  description = "Unity Catalog external locations keyed by stable caller-defined identifiers."
  type = map(object({
    name            = string
    url             = string
    credential_key  = string
    comment         = optional(string)
    owner           = optional(string)
    read_only       = optional(bool, false)
    skip_validation = optional(bool, false)
    fallback        = optional(bool, false)
    encryption_details = optional(object({
      sse_encryption_details = object({
        algorithm       = string
        aws_kms_key_arn = optional(string)
      })
    }))
    workspace_access_mode = optional(string, "ISOLATION_MODE_ISOLATED")
    workspace_ids         = optional(list(string), [])
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))

  validation {
    condition = !var.enabled || alltrue([
      for location in values(var.external_locations) :
      contains(keys(var.storage_credentials), location.credential_key)
    ])
    error_message = "Each external location credential_key must reference an existing storage_credentials key."
  }

  validation {
    condition = !var.enabled || alltrue([
      for location in values(var.external_locations) :
      contains(["ISOLATION_MODE_ISOLATED", "ISOLATION_MODE_OPEN"], location.workspace_access_mode)
    ])
    error_message = "Each external location workspace_access_mode must be ISOLATION_MODE_ISOLATED or ISOLATION_MODE_OPEN."
  }

  validation {
    condition = !var.enabled || alltrue([
      for location in values(var.external_locations) :
      location.workspace_access_mode != "ISOLATION_MODE_OPEN" || length(location.workspace_ids) == 0
    ])
    error_message = "External locations with workspace_access_mode = ISOLATION_MODE_OPEN must not declare workspace_ids."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for location in values(var.external_locations) : [
        for workspace_id in location.workspace_ids :
        trimspace(workspace_id) != "" && can(tonumber(workspace_id))
      ]
    ]))
    error_message = "External location workspace_ids must be non-empty numeric strings."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for location in values(var.external_locations) : [
        for grant in location.grants : length(grant.privileges) > 0
      ]
    ]))
    error_message = "Each external location grant must declare at least one privilege."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for location in values(var.external_locations) : [
        for grant in location.grants : [
          for privilege in grant.privileges :
          contains([
            "ALL_PRIVILEGES",
            "BROWSE",
            "CREATE_EXTERNAL_TABLE",
            "CREATE_EXTERNAL_VOLUME",
            "CREATE_FOREIGN_SECURABLE",
            "CREATE_MANAGED_STORAGE",
            "EXTERNAL_USE_LOCATION",
            "MANAGE",
            "READ_FILES",
            "WRITE_FILES"
          ], privilege)
        ]
      ]
    ]))
    error_message = "External location grant privileges must be one of: ALL_PRIVILEGES, BROWSE, CREATE_EXTERNAL_TABLE, CREATE_EXTERNAL_VOLUME, CREATE_FOREIGN_SECURABLE, CREATE_MANAGED_STORAGE, EXTERNAL_USE_LOCATION, MANAGE, READ_FILES, WRITE_FILES."
  }
}
