resource "terraform_data" "policy" {
  for_each = var.policies

  input = each.value

  lifecycle {
    precondition {
      condition = alltrue([
        for tag in each.value.tags :
        tag.actual == tag.key &&
        (tag.value == null || contains(tag.allowed, tag.value))
      ])
      error_message = "Policy ${each.key} references a governed tag key or allowed value that does not exist."
    }

    precondition {
      condition     = contains(each.value.function.available, each.value.function.name)
      error_message = "Policy ${each.key} references Unity Catalog function ${each.value.function.name}, which does not exist."
    }
  }
}
