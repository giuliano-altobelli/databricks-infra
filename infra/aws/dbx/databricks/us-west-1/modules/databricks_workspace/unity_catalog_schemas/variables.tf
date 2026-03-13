variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "schemas" {
  description = "Unity Catalog schemas keyed by stable caller-defined identifiers."
  type = map(object({
    catalog_name = string
    schema_name  = string
    comment      = optional(string)
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))

  validation {
    condition = !var.enabled || alltrue([
      for schema in values(var.schemas) :
      trimspace(schema.catalog_name) != "" &&
      trimspace(schema.schema_name) != ""
    ])
    error_message = "Each schema must declare non-empty catalog_name and schema_name values."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for schema in values(var.schemas) : [
        for grant in schema.grants : trimspace(grant.principal) != ""
      ]
    ]))
    error_message = "Each schema grant principal must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for schema in values(var.schemas) : [
        for grant in schema.grants : length(grant.privileges) > 0
      ]
    ]))
    error_message = "Each schema grant must declare at least one privilege."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for schema in values(var.schemas) : [
        for grant in schema.grants : [
          for privilege in grant.privileges :
          contains(["ALL_PRIVILEGES", "USE_SCHEMA"], privilege)
        ]
      ]
    ]))
    error_message = "Schema grant privileges must be one of: ALL_PRIVILEGES, USE_SCHEMA."
  }
}
