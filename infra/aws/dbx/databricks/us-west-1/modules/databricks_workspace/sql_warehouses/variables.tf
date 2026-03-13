variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "sql_warehouses" {
  description = "SQL warehouses keyed by stable caller-defined identifiers."
  type = map(object({
    name                      = string
    cluster_size              = string
    max_num_clusters          = number
    enable_serverless_compute = bool
    permissions = list(object({
      principal_type   = string
      principal_name   = string
      permission_level = optional(string, "CAN_USE")
    }))
    min_num_clusters     = optional(number)
    auto_stop_mins       = optional(number)
    spot_instance_policy = optional(string)
    enable_photon        = optional(bool)
    warehouse_type       = optional(string)
    no_wait              = optional(bool)
    channel = optional(object({
      name = optional(string, "CHANNEL_NAME_CURRENT")
    }))
    tags = optional(map(string))
  }))

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      length(warehouse.permissions) > 0
    ])
    error_message = "Each SQL warehouse must declare at least one permission entry."
  }

  validation {
    condition = !var.enabled || length([
      for warehouse in values(var.sql_warehouses) : warehouse.name
      ]) == length(toset([
        for warehouse in values(var.sql_warehouses) : warehouse.name
    ]))
    error_message = "Managed SQL warehouse names must be unique across sql_warehouses."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for warehouse in values(var.sql_warehouses) : [
        for grant in warehouse.permissions :
        contains(["group", "user", "service_principal"], grant.principal_type)
      ]
    ]))
    error_message = "Each permission principal_type must be one of: group, user, service_principal."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for warehouse in values(var.sql_warehouses) : [
        for grant in warehouse.permissions :
        contains(["CAN_USE", "CAN_MONITOR", "CAN_MANAGE", "CAN_VIEW", "IS_OWNER"], coalesce(try(grant.permission_level, null), "CAN_USE"))
      ]
    ]))
    error_message = "Each permission permission_level must be one of: CAN_USE, CAN_MONITOR, CAN_MANAGE, CAN_VIEW, IS_OWNER."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      contains(["2X-Small", "X-Small", "Small", "Medium", "Large", "X-Large", "2X-Large", "3X-Large", "4X-Large"], warehouse.cluster_size)
    ])
    error_message = "Each SQL warehouse cluster_size must match the Databricks SQL warehouse supported sizes."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.spot_instance_policy, null) == null || contains(["COST_OPTIMIZED", "RELIABILITY_OPTIMIZED"], warehouse.spot_instance_policy)
    ])
    error_message = "Each SQL warehouse spot_instance_policy must be COST_OPTIMIZED or RELIABILITY_OPTIMIZED when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.warehouse_type, null) == null || contains(["PRO", "CLASSIC"], warehouse.warehouse_type)
    ])
    error_message = "Each SQL warehouse warehouse_type must be PRO or CLASSIC when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.channel.name, null) == null || contains(["CHANNEL_NAME_CURRENT", "CHANNEL_NAME_PREVIEW"], warehouse.channel.name)
    ])
    error_message = "Each SQL warehouse channel.name must be CHANNEL_NAME_CURRENT or CHANNEL_NAME_PREVIEW when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      warehouse.max_num_clusters > 0 && floor(warehouse.max_num_clusters) == warehouse.max_num_clusters
    ])
    error_message = "Each SQL warehouse max_num_clusters must be a positive integer."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.min_num_clusters, null) == null || (warehouse.min_num_clusters > 0 && floor(warehouse.min_num_clusters) == warehouse.min_num_clusters)
    ])
    error_message = "Each SQL warehouse min_num_clusters must be a positive integer when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.min_num_clusters, null) == null || warehouse.max_num_clusters >= warehouse.min_num_clusters
    ])
    error_message = "Each SQL warehouse max_num_clusters must be greater than or equal to min_num_clusters."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      !warehouse.enable_serverless_compute || coalesce(try(warehouse.warehouse_type, null), "PRO") != "CLASSIC"
    ])
    error_message = "SQL warehouses with enable_serverless_compute = true must not set warehouse_type = CLASSIC."
  }
}
