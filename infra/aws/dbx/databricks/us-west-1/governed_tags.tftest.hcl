mock_provider "aws" {}
mock_provider "aws" {
  alias = "us_west_1"
}
mock_provider "databricks" {}
mock_provider "databricks" {
  alias = "mws"
}
mock_provider "databricks" {
  alias = "created_workspace"
}

variables {
  admin_user            = "administrator@example.com"
  aws_account_id        = "111111111111"
  compliance_standards  = []
  databricks_account_id = "11111111-1111-1111-1111-111111111111"
  metastore_exists      = true
  region                = "us-west-2"
  resource_prefix       = "test"

  abac = {
    name    = "policy"
    comment = "Policy."
    table = {
      key   = "boundary"
      value = "general"
    }
    column = {
      key   = "protected"
      value = "groups"
      alias = "groups"
    }
    function = {
      schema = "security"
      name   = "filter"
    }
    principals = {
      include = ["users"]
      exclude = []
    }
  }
}

run "tags" {
  command = plan

  plan_options {
    target = [module.governance]
  }

  override_module {
    target = module.databricks_mws_workspace
    outputs = {
      workspace_id  = "1111111111111111"
      workspace_url = "https://example.cloud.databricks.com"
    }
  }

  override_data {
    target = data.databricks_aws_assume_role_policy.this
    values = {
      json = "{}"
    }
  }

  override_data {
    target = data.databricks_aws_crossaccount_policy.this
    values = {
      json = "{}"
    }
  }

  assert {
    condition = (
      local.tags.reviewed.description == "Indicates that an object has completed review." &&
      try(length(local.tags.reviewed.values), 0) == 0
    )
    error_message = "The reviewed governed tag must be key-only."
  }

  assert {
    condition = (
      local.tags.lifecycle.description == "Identifies the lifecycle stage of an object." &&
      local.tags.lifecycle.values == ["development", "production", "retired"]
    )
    error_message = "The lifecycle governed tag must declare its configured allowed values."
  }
}
