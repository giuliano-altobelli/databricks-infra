variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "bedrock_external_model_endpoints" {
  description = "Bedrock external model serving endpoints keyed by stable caller-defined identifiers."
  type = map(object({
    name                 = string
    aws_region           = string
    instance_profile_arn = string
    served_entities = map(object({
      name               = string
      task               = string
      bedrock_provider   = string
      bedrock_model      = string
      traffic_percentage = number
    }))
    permissions = list(object({
      principal_type   = string
      principal_name   = string
      permission_level = optional(string, "CAN_QUERY")
    }))
  }))

  validation {
    condition     = !var.enabled || length(var.bedrock_external_model_endpoints) > 0
    error_message = "At least one Bedrock external model endpoint must be declared when enabled = true."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      trimspace(endpoint.name) != "" &&
      trimspace(endpoint.aws_region) != "" &&
      trimspace(endpoint.instance_profile_arn) != ""
    ])
    error_message = "Each endpoint name, aws_region, and instance_profile_arn must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:instance-profile/.+", endpoint.instance_profile_arn))
    ])
    error_message = "Each endpoint instance_profile_arn must be a valid AWS IAM instance profile ARN."
  }

  validation {
    condition = !var.enabled || length([
      for endpoint in values(var.bedrock_external_model_endpoints) : endpoint.name
      ]) == length(toset([
        for endpoint in values(var.bedrock_external_model_endpoints) : endpoint.name
    ]))
    error_message = "Managed Bedrock external model endpoint names must be unique."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      length(endpoint.served_entities) > 0 && length(endpoint.served_entities) <= 10
    ])
    error_message = "Each endpoint must declare between 1 and 10 served_entities."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for served_entity in values(endpoint.served_entities) :
        trimspace(served_entity.name) != "" &&
        trimspace(served_entity.task) != "" &&
        trimspace(served_entity.bedrock_provider) != "" &&
        trimspace(served_entity.bedrock_model) != ""
      ]
    ]))
    error_message = "Each served entity name, task, bedrock_provider, and bedrock_model must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      length([
        for served_entity in values(endpoint.served_entities) : served_entity.name
        ]) == length(toset([
          for served_entity in values(endpoint.served_entities) : served_entity.name
      ]))
    ])
    error_message = "Served entity names must be unique within each endpoint."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      length(toset([
        for served_entity in values(endpoint.served_entities) : served_entity.task
      ])) == 1
    ])
    error_message = "All served entities within an endpoint must use the same task."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for served_entity in values(endpoint.served_entities) :
        contains(["llm/v1/chat", "llm/v1/completions", "llm/v1/embeddings"], served_entity.task)
      ]
    ]))
    error_message = "Each served entity task must be one of: llm/v1/chat, llm/v1/completions, llm/v1/embeddings."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for served_entity in values(endpoint.served_entities) :
        contains(["anthropic", "cohere", "ai21labs", "amazon"], lower(served_entity.bedrock_provider))
      ]
    ]))
    error_message = "Each served entity bedrock_provider must be one of: Anthropic, Cohere, AI21Labs, Amazon."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for served_entity in values(endpoint.served_entities) :
        served_entity.traffic_percentage >= 0 &&
        served_entity.traffic_percentage <= 100 &&
        floor(served_entity.traffic_percentage) == served_entity.traffic_percentage
      ]
    ]))
    error_message = "Each served entity traffic_percentage must be an integer from 0 through 100."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      sum([
        for served_entity in values(endpoint.served_entities) : served_entity.traffic_percentage
      ]) == 100
    ])
    error_message = "Served entity traffic_percentage values must sum to 100 for each endpoint."
  }

  validation {
    condition = !var.enabled || alltrue([
      for endpoint in values(var.bedrock_external_model_endpoints) :
      length(endpoint.permissions) > 0
    ])
    error_message = "Each endpoint must declare at least one permission entry."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for grant in endpoint.permissions :
        contains(["group", "user", "service_principal"], grant.principal_type)
      ]
    ]))
    error_message = "Each permission principal_type must be one of: group, user, service_principal."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for grant in endpoint.permissions :
        trimspace(grant.principal_name) != ""
      ]
    ]))
    error_message = "Each permission principal_name must be non-empty."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for endpoint in values(var.bedrock_external_model_endpoints) : [
        for grant in endpoint.permissions :
        contains(["CAN_VIEW", "CAN_QUERY", "CAN_MANAGE"], coalesce(try(grant.permission_level, null), "CAN_QUERY"))
      ]
    ]))
    error_message = "Each permission permission_level must be one of: CAN_VIEW, CAN_QUERY, CAN_MANAGE."
  }
}
