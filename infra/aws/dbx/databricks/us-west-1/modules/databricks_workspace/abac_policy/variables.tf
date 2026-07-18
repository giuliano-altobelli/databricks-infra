variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "dependencies" {
  description = "External prerequisite resource identifiers that must exist before policy creation."
  type        = set(string)
  default     = []
}

variable "policies" {
  description = "Unity Catalog ABAC row-filter policies keyed by policy name."
  type = map(object({
    scope = object({
      catalog = string
      schema  = optional(string)
    })
    principals = object({
      include = set(string)
      exclude = optional(set(string), [])
    })
    table = optional(object({
      key   = string
      value = optional(string)
    }))
    columns = object({
      first = optional(object({
        key   = string
        value = optional(string)
        alias = string
      }))
      second = optional(object({
        key   = string
        value = optional(string)
        alias = string
      }))
      third = optional(object({
        key   = string
        value = optional(string)
        alias = string
      }))
    })
    function = string
    comment  = optional(string)
  }))
  default = {}

  validation {
    condition = !var.enabled || alltrue([
      for name in keys(var.policies) : trimspace(name) != ""
    ])
    error_message = "Policy names must be non-empty."
  }

  validation {
    condition = !var.enabled || length(var.policies) == length(distinct([
      for name in keys(var.policies) : lower(trimspace(name))
    ]))
    error_message = "Policy names must be unique after trimming whitespace and lowercasing."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) :
      trimspace(policy.scope.catalog) != "" &&
      (policy.scope.schema == null || trimspace(policy.scope.schema) != "")
    ])
    error_message = "Each policy scope must declare a non-empty catalog and an optional non-empty schema."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) : length(policy.principals.include) > 0
    ])
    error_message = "Each policy must include at least one principal."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) : policy.columns.first != null
    ])
    error_message = "Each policy must declare its first column tag selector."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for policy in values(var.policies) : [
        for principal in setunion(policy.principals.include, policy.principals.exclude) :
        trimspace(principal) != ""
      ]
    ]))
    error_message = "Policy principals must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) :
      length(policy.principals.include) == length(distinct([
        for principal in policy.principals.include : lower(trimspace(principal))
      ])) &&
      length(policy.principals.exclude) == length(distinct([
        for principal in policy.principals.exclude : lower(trimspace(principal))
      ]))
    ])
    error_message = "Included and excluded principals must each be unique after trimming whitespace and lowercasing."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) :
      policy.table == null || (
        trimspace(policy.table.key) != "" &&
        (policy.table.value == null || trimspace(policy.table.value) != "")
      )
    ])
    error_message = "Each table tag selector must declare a non-empty key and an optional non-empty value."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for policy in values(var.policies) : [
        for column in [policy.columns.first, policy.columns.second, policy.columns.third] :
        trimspace(column.key) != "" &&
        trimspace(column.alias) != "" &&
        (column.value == null || trimspace(column.value) != "")
        if column != null
      ]
    ]))
    error_message = "Each column tag selector must declare a non-empty key, alias, and optional non-empty value."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) :
      length([
        for column in [policy.columns.first, policy.columns.second, policy.columns.third] : column
        if column != null
        ]) == length(distinct([
          for column in [policy.columns.first, policy.columns.second, policy.columns.third] : lower(trimspace(column.alias))
          if column != null
      ]))
    ])
    error_message = "Column aliases must be unique per policy after trimming whitespace and lowercasing."
  }

  validation {
    condition = !var.enabled || alltrue([
      for policy in values(var.policies) :
      length(split(".", trimspace(policy.function))) == 3 &&
      alltrue([
        for part in split(".", trimspace(policy.function)) : trimspace(part) != ""
      ])
    ])
    error_message = "Each policy function must be a three-part Unity Catalog name in catalog.schema.function form."
  }
}
