variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "aws_account_id" {
  type        = string
  description = "ID of the AWS account."
}

variable "aws_iam_partition" {
  type        = string
  description = "AWS partition to use for IAM ARNs and policies"
  default     = "aws"
}

variable "aws_assume_partition" {
  type        = string
  description = "AWS partition to use for assume role policies"
  default     = "aws"
}

variable "unity_catalog_iam_arn" {
  type        = string
  description = "Unity Catalog IAM ARN for the master role"
  default     = "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
}

variable "cmk_admin_arn" {
  description = "Amazon Resource Name (ARN) of the CMK admin."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for the resource names."
  type        = string
}

variable "catalog_name" {
  description = "Unity Catalog catalog name."
  type        = string

  validation {
    condition     = !var.enabled || trimspace(var.catalog_name) != ""
    error_message = "catalog_name must be non-empty when enabled is true."
  }
}

variable "catalog_admin_principal" {
  description = "Principal that receives catalog admin privileges."
  type        = string

  validation {
    condition     = !var.enabled || trimspace(var.catalog_admin_principal) != ""
    error_message = "catalog_admin_principal must be non-empty when enabled is true."
  }
}

variable "catalog_reader_principals" {
  description = "Principals that receive catalog-level reader privileges."
  type        = list(string)
  default     = []

  validation {
    condition = !var.enabled || alltrue([
      for principal in var.catalog_reader_principals :
      trimspace(principal) != ""
    ])
    error_message = "catalog_reader_principals must contain only non-empty principals when enabled is true."
  }

  validation {
    condition = !var.enabled || (
      length([for principal in var.catalog_reader_principals : trimspace(principal)]) ==
      length(distinct([for principal in var.catalog_reader_principals : trimspace(principal)]))
    )
    error_message = "catalog_reader_principals must contain unique principals when enabled is true."
  }
}

variable "workspace_id" {
  description = "workspace ID of deployed workspace."
  type        = string

  validation {
    condition     = !var.enabled || trimspace(var.workspace_id) != ""
    error_message = "workspace_id must be non-empty when enabled is true."
  }

  validation {
    condition     = !var.enabled || can(tonumber(var.workspace_id))
    error_message = "workspace_id must be numeric when enabled is true."
  }
}

variable "workspace_ids" {
  description = "Additional workspace IDs that receive isolated workspace bindings."
  type        = list(string)
  default     = []

  validation {
    condition = !var.enabled || alltrue([
      for workspace_id in var.workspace_ids :
      trimspace(workspace_id) != "" && can(tonumber(workspace_id))
    ])
    error_message = "workspace_ids must contain only non-empty numeric strings when enabled is true."
  }
}

variable "set_default_namespace" {
  description = "Whether to manage the workspace default namespace for this catalog."
  type        = bool
  default     = false
}
