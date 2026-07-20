output "tags" {
  description = "Managed governed tags keyed by their exact tag key."
  value = {
    for key, tag in databricks_tag_policy.tag : key => {
      id          = tag.id
      key         = tag.tag_key
      description = tag.description
      values      = [for value in tag.values : value.name]
    }
  }
}
