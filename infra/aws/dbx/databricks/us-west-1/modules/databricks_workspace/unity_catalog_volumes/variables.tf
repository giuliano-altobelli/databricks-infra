# Module inputs.
#
# Keep variable descriptions crisp. Prefer `optional(...)` types and defaults where sensible.

variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

