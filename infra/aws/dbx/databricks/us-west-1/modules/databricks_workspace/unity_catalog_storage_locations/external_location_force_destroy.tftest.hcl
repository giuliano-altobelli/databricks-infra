mock_provider "databricks" {}

run "external_location_force_destroy_is_passed_to_provider" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    storage_credentials = {
      bronze_raw = {
        name     = "bronze-raw-storage-credential"
        role_arn = "arn:aws:iam::123456789012:role/databricks-bronze-raw"
      }
    }

    external_locations = {
      bronze_raw_root = {
        name           = "bronze-raw-root"
        url            = "s3://company-bronze-raw/"
        credential_key = "bronze_raw"
        force_destroy  = true
      }
    }
  }

  assert {
    condition     = databricks_external_location.this["bronze_raw_root"].force_destroy == true
    error_message = "External location force_destroy must be passed through to databricks_external_location."
  }
}
