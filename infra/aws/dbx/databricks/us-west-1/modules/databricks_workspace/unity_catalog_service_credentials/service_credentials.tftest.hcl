mock_provider "databricks" {}

run "aws_service_credential_shape" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      bedrock_runtime = {
        name = "sandbox-bedrock-runtime-service-credential"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-sandbox-bedrock-runtime"
        }
        comment         = "Sandbox Bedrock runtime service credential."
        skip_validation = true
        force_update    = true
        grants = [
          {
            principal = "Data Engineers"
          },
          {
            principal  = "00000000-0000-0000-0000-000000000000"
            privileges = ["ACCESS"]
          },
        ]
      }
    }
  }

  assert {
    condition     = databricks_credential.this["bedrock_runtime"].purpose == "SERVICE"
    error_message = "Service credentials must be created with purpose = SERVICE."
  }

  assert {
    condition     = databricks_credential.this["bedrock_runtime"].aws_iam_role[0].role_arn == "arn:aws:iam::123456789012:role/databricks-sandbox-bedrock-runtime"
    error_message = "AWS IAM role ARN must be passed into databricks_credential.aws_iam_role."
  }

  assert {
    condition     = databricks_credential.this["bedrock_runtime"].skip_validation == true
    error_message = "skip_validation must be passed through to databricks_credential."
  }

  assert {
    condition = length([
      for grant in databricks_grants.credential["bedrock_runtime"].grant : grant
      if grant.principal == "Data Engineers" && contains(grant.privileges, "ACCESS")
    ]) == 1
    error_message = "Grant privileges must default to ACCESS when omitted."
  }

  assert {
    condition     = databricks_workspace_binding.credential["bedrock_runtime:1234567890123456"].securable_type == "credential"
    error_message = "Isolated service credentials must bind the current workspace as credential securables."
  }
}

run "open_mode_creates_no_workspace_bindings" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      shared_api = {
        name                  = "sandbox-shared-api-service-credential"
        workspace_access_mode = "ISOLATION_MODE_OPEN"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-shared-api"
        }
      }
    }
  }

  assert {
    condition     = databricks_credential.this["shared_api"].isolation_mode == "ISOLATION_MODE_OPEN"
    error_message = "Open mode must pass ISOLATION_MODE_OPEN to databricks_credential."
  }

  assert {
    condition     = length(databricks_workspace_binding.credential) == 0
    error_message = "Open mode service credentials must not create explicit workspace bindings."
  }
}

run "disabled_outputs_empty" {
  command = plan

  variables {
    enabled              = false
    current_workspace_id = ""

    service_credentials = {
      ignored = {
        name = ""
        aws = {
          role_arn = ""
        }
      }
    }
  }

  assert {
    condition     = length(output.service_credentials) == 0
    error_message = "service_credentials output must be empty when the module is disabled."
  }

  assert {
    condition     = length(output.workspace_binding_ids) == 0
    error_message = "workspace_binding_ids output must be empty when the module is disabled."
  }
}

run "reject_malformed_role_arn" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name = "invalid-service-credential"
        aws = {
          role_arn = "not-an-iam-role-arn"
        }
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_open_mode_with_workspace_ids" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name                  = "invalid-open-service-credential"
        workspace_access_mode = "ISOLATION_MODE_OPEN"
        workspace_ids         = ["1234567890123456"]
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-invalid-open"
        }
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_non_access_grant" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name = "invalid-privilege-service-credential"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-invalid-privilege"
        }
        grants = [
          {
            principal  = "Data Engineers"
            privileges = ["MANAGE"]
          }
        ]
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_blank_grant_principal" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name = "blank-principal-service-credential"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-blank-principal"
        }
        grants = [
          {
            principal = "  "
          }
        ]
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_empty_grant_privileges" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name = "empty-privileges-service-credential"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-empty-privileges"
        }
        grants = [
          {
            principal  = "Data Engineers"
            privileges = []
          }
        ]
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_invalid_workspace_access_mode" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name                  = "invalid-mode-service-credential"
        workspace_access_mode = "ISOLATION_MODE_UNKNOWN"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-invalid-mode"
        }
      }
    }
  }

  expect_failures = [
    var.service_credentials,
  ]
}

run "reject_duplicate_workspace_bindings" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name          = "duplicate-binding-service-credential"
        workspace_ids = ["1234567890123456"]
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-duplicate-binding"
        }
      }
    }
  }

  expect_failures = [
    databricks_credential.this,
  ]
}

run "reject_duplicate_grant_tuples" {
  command = plan

  variables {
    current_workspace_id = "1234567890123456"

    service_credentials = {
      invalid = {
        name = "duplicate-grant-service-credential"
        aws = {
          role_arn = "arn:aws:iam::123456789012:role/databricks-duplicate-grant"
        }
        grants = [
          {
            principal  = "Data Engineers"
            privileges = ["ACCESS"]
          },
          {
            principal  = "Data Engineers"
            privileges = ["ACCESS"]
          },
        ]
      }
    }
  }

  expect_failures = [
    databricks_credential.this,
  ]
}
