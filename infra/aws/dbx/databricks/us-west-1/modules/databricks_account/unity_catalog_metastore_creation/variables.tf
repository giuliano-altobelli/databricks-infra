variable "metastore_exists" {
  description = "If a metastore exists."
  type        = bool
}

variable "metastore_storage_root" {
  description = "Storage root for a new metastore."
  type        = string
  default     = null
  nullable    = true
}

variable "region" {
  description = "AWS region code."
  type        = string
}
