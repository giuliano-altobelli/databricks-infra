locals {
  tags = var.enabled ? var.tags : {}
}

resource "databricks_tag_policy" "tag" {
  for_each = local.tags

  tag_key     = each.key
  description = each.value.description
  values = [
    for value in sort(tolist(each.value.values)) : {
      name = value
    }
  ]

  lifecycle {
    precondition {
      condition     = try(trimspace(each.value.description) != "", false)
      error_message = "Governed tag descriptions must be non-empty."
    }

    precondition {
      condition = alltrue([
        for name in setunion(toset([each.key]), each.value.values) :
        length(name) > 0 && length(name) <= 256
      ])
      error_message = "Governed tag keys and allowed values must contain between 1 and 256 characters."
    }

    precondition {
      condition = alltrue([
        for name in setunion(toset([each.key]), each.value.values) :
        trimspace(name) == name
      ])
      error_message = "Governed tag keys and allowed values must not contain leading or trailing whitespace."
    }

    precondition {
      condition = alltrue([
        for name in setunion(toset([each.key]), each.value.values) :
        !can(regex("[*./<>%&?\\\\=]|[\\x00-\\x1F]", name))
      ])
      error_message = "Governed tag keys and allowed values must not contain *, ., /, <, >, %, &, ?, \\, =, or ASCII control characters."
    }
  }
}
