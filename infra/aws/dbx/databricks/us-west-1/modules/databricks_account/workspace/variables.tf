variable "backend_relay" {
  description = "ID of the backend relay API interface endpoint."
  type        = string
  default     = null
  nullable    = true
}

variable "backend_rest" {
  description = "ID of the backend rest API interface endpoint."
  type        = string
  default     = null
  nullable    = true
}

variable "bucket_name" {
  description = "Name of the root S3 bucket for the workspace."
  type        = string
}

variable "cross_account_role_arn" {
  description = "AWS ARN of the cross-account role."
  type        = string
}

variable "databricks_account_id" {
  description = "ID of the Databricks account."
  type        = string
}

variable "deployment_name" {
  description = "Deployment name for the workspace. Must first be enabled by a Databricks representative."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_customer_managed_keys" {
  description = "Enable customer-managed key resources and workspace key attachments."
  type        = bool
  default     = true
}

variable "enable_customer_managed_network" {
  description = "Enable customer-managed network resources and network attachment on workspace creation."
  type        = bool
  default     = true
}

variable "enable_ncc_binding" {
  description = "Enable NCC binding attachment for the workspace."
  type        = bool
  default     = true
}

variable "enable_network_policy_attachment" {
  description = "Enable network policy attachment for the workspace."
  type        = bool
  default     = true
}

variable "enable_private_access_settings" {
  description = "Enable private access settings and workspace PAS attachment."
  type        = bool
  default     = true
}

variable "managed_services_key" {
  description = "CMK for managed services."
  type        = string
  default     = null
  nullable    = true
}

variable "managed_services_key_alias" {
  description = "CMK for managed services alias."
  type        = string
  default     = null
  nullable    = true
}

variable "network_policy_id" {
  description = "Network policy ID for serverless compute."
  type        = string
  default     = null
  nullable    = true
}

variable "network_connectivity_configuration_id" {
  description = "Network connectivity configuration ID."
  type        = string
  default     = null
  nullable    = true
}

variable "pricing_tier" {
  description = "Pricing tier used when creating the Databricks workspace."
  type        = string
  default     = "ENTERPRISE"
}

variable "region" {
  description = "AWS region code."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for the resource names."
  type        = string
}

variable "security_group_ids" {
  description = "Security group ID"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_storage_key" {
  description = "CMK for workspace storage."
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_storage_key_alias" {
  description = "CMK for workspace storage alias."
  type        = string
  default     = null
  nullable    = true
}
