variable "enabled" {
  description = "Whether this module manages governed tags."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "User-defined governed tags keyed by their exact tag key."
  type = map(object({
    description = string
    values      = optional(set(string), [])
  }))
  default  = {}
  nullable = false
}
