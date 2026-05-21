locals {
  enabled_tables = var.enabled ? var.tables : {}

  table_full_names = {
    for table_key, table in local.enabled_tables :
    table_key => format(
      "%s.%s.%s",
      table.catalog_name,
      table.schema_name,
      table.table_name
    )
  }
}

resource "databricks_grants" "table" {
  for_each = local.enabled_tables

  table = local.table_full_names[each.key]

  dynamic "grant" {
    for_each = toset(each.value.reader_principals)

    content {
      principal  = grant.value
      privileges = ["SELECT"]
    }
  }
}
