variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "volumes" {
  description = "Unity Catalog volumes keyed by stable caller-defined identifiers."
  type = map(object({
    name             = string
    catalog_name     = string
    schema_name      = string
    volume_type      = string
    comment          = optional(string)
    owner            = optional(string)
    storage_location = optional(string)
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))

  validation {
    condition = !var.enabled || alltrue([
      for volume in values(var.volumes) :
      trimspace(volume.name) != "" &&
      trimspace(volume.catalog_name) != "" &&
      trimspace(volume.schema_name) != ""
    ])
    error_message = "Each volume must declare non-empty name, catalog_name, and schema_name values."
  }

  validation {
    condition = !var.enabled || alltrue([
      for volume in values(var.volumes) :
      contains(["MANAGED", "EXTERNAL"], volume.volume_type)
    ])
    error_message = "Each volume volume_type must be MANAGED or EXTERNAL."
  }

  validation {
    condition = !var.enabled || alltrue([
      for volume in values(var.volumes) :
      volume.volume_type != "EXTERNAL" || (
        try(volume.storage_location, null) == null ? false : trimspace(volume.storage_location) != ""
      )
    ])
    error_message = "EXTERNAL volumes must declare a non-empty storage_location."
  }

  validation {
    condition = !var.enabled || alltrue([
      for volume in values(var.volumes) :
      volume.volume_type != "MANAGED" || (
        try(volume.storage_location, null) == null ? true : trimspace(volume.storage_location) == ""
      )
    ])
    error_message = "MANAGED volumes must not declare storage_location."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for volume in values(var.volumes) : [
        for grant in volume.grants : trimspace(grant.principal) != ""
      ]
    ]))
    error_message = "Each volume grant principal must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for volume in values(var.volumes) : [
        for grant in volume.grants : length(grant.privileges) > 0
      ]
    ]))
    error_message = "Each volume grant must declare at least one privilege."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for volume in values(var.volumes) : [
        for grant in volume.grants : [
          for privilege in grant.privileges :
          contains(["ALL_PRIVILEGES", "APPLY_TAG", "MANAGE", "READ_VOLUME", "WRITE_VOLUME"], privilege)
        ]
      ]
    ]))
    error_message = "Volume grant privileges must be one of: ALL_PRIVILEGES, APPLY_TAG, MANAGE, READ_VOLUME, WRITE_VOLUME."
  }
}
