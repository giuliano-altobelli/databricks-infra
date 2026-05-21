mock_provider "databricks" {}

run "reject_duplicate_table_identities" {
  command = plan

  variables {
    tables = {
      first = {
        catalog_name      = "Finance"
        schema_name       = "Raw"
        table_name        = "Transactions"
        reader_principals = ["Finance Readers"]
      }
      second = {
        catalog_name      = " finance "
        schema_name       = "raw"
        table_name        = "transactions"
        reader_principals = ["Risk Readers"]
      }
    }
  }

  expect_failures = [
    var.tables,
  ]
}

run "reject_empty_reader_principals" {
  command = plan

  variables {
    tables = {
      transactions = {
        catalog_name      = "finance"
        schema_name       = "raw"
        table_name        = "transactions"
        reader_principals = []
      }
    }
  }

  expect_failures = [
    var.tables,
  ]
}
