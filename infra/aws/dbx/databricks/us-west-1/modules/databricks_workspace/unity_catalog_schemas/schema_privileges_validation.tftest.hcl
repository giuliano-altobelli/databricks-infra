mock_provider "databricks" {}

run "accept_schema_object_privileges" {
  command = plan

  variables {
    schemas = {
      finance_raw = {
        catalog_name = "finance"
        schema_name  = "raw"
        grants = [
          {
            principal = "Finance Readers"
            privileges = [
              "CREATE_FUNCTION",
              "CREATE MATERIALIZED VIEW",
              "CREATE_TABLE",
              "EXECUTE",
              "SELECT",
              "USE_SCHEMA",
            ]
          },
        ]
      }
    }
  }
}
