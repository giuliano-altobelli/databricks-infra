variable "enabled" {
  type    = bool
  default = true
}

variable "region" {
  type = string

  validation {
    condition = contains([
      "ap-northeast-1",
      "ap-northeast-2",
      "ap-south-1",
      "ap-southeast-1",
      "ap-southeast-2",
      "ap-southeast-3",
      "ca-central-1",
      "eu-central-1",
      "eu-west-1",
      "eu-west-2",
      "eu-west-3",
      "sa-east-1",
      "us-east-1",
      "us-east-2",
      "us-west-1",
      "us-west-2",
      "us-gov-west-1",
    ], var.region)
    error_message = "Valid values for var: region are (ap-northeast-1, ap-northeast-2, ap-south-1, ap-southeast-1, ap-southeast-2, ap-southeast-3, ca-central-1, eu-central-1, eu-west-1, eu-west-2, eu-west-3, sa-east-1, us-east-1, us-east-2, us-west-1, us-west-2, us-gov-west-1)."
  }
}

variable "name_prefix" {
  type = string

  validation {
    condition     = trimspace(var.name_prefix) != ""
    error_message = "name_prefix must be non-empty."
  }
}

variable "service_principals" {
  type = map(object({
    display_name = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for principal_key in keys(var.service_principals) :
      trimspace(principal_key) != ""
    ])
    error_message = "service_principals map keys must be non-empty."
  }
}
