variable "policies" {
  description = "Resolved governed-tag and Unity Catalog function inventories keyed by policy name."
  type = map(object({
    tags = list(object({
      key     = string
      actual  = string
      value   = optional(string)
      allowed = set(string)
    }))
    function = object({
      name      = string
      available = set(string)
    })
  }))
}
