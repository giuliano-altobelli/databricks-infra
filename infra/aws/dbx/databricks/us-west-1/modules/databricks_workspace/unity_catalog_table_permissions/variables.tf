variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "tables" {
  description = "Existing Unity Catalog managed tables keyed by stable caller-defined identifiers."
  type = map(object({
    catalog_name      = string
    schema_name       = string
    table_name        = string
    reader_principals = list(string)
  }))

  validation {
    condition = !var.enabled || alltrue([
      for table in values(var.tables) :
      trimspace(table.catalog_name) != "" &&
      trimspace(table.schema_name) != "" &&
      trimspace(table.table_name) != ""
    ])
    error_message = "Each table must declare non-empty catalog_name, schema_name, and table_name values."
  }

  validation {
    condition = !var.enabled || alltrue([
      for table in values(var.tables) :
      length(table.reader_principals) > 0
    ])
    error_message = "Each table must declare at least one reader principal."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for table in values(var.tables) : [
        for principal in table.reader_principals :
        trimspace(principal) != ""
      ]
    ]))
    error_message = "Reader principals must be non-empty after trimming whitespace."
  }

  validation {
    condition = !var.enabled || alltrue([
      for table in values(var.tables) :
      length(table.reader_principals) == length(distinct([
        for principal in table.reader_principals :
        lower(trimspace(principal))
      ]))
    ])
    error_message = "Reader principals must be unique per table after trimming whitespace and lowercasing."
  }

  validation {
    condition = !var.enabled || length([
      for table in values(var.tables) :
      format(
        "%s.%s.%s",
        lower(trimspace(table.catalog_name)),
        lower(trimspace(table.schema_name)),
        lower(trimspace(table.table_name))
      )
      ]) == length(distinct([
        for table in values(var.tables) :
        format(
          "%s.%s.%s",
          lower(trimspace(table.catalog_name)),
          lower(trimspace(table.schema_name)),
          lower(trimspace(table.table_name))
        )
    ]))
    error_message = "Duplicate table identities are not allowed after trimming whitespace and lowercasing catalog_name, schema_name, and table_name."
  }
}
