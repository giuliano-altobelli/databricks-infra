mock_provider "databricks" {}

run "catalog" {
  command = plan

  variables {
    policies = {
      restrict_region = {
        scope = {
          catalog = "governed"
        }
        principals = {
          include = ["account users"]
        }
        columns = {
          first = {
            key   = "region"
            alias = "region"
          }
        }
        function = "governed.security.filter_region"
      }
    }
  }

  override_module {
    target  = module.validation
    outputs = {}
  }

  assert {
    condition     = databricks_policy_info.policy["restrict_region"].on_securable_type == "CATALOG"
    error_message = "A scope without schema must create a catalog policy."
  }

  assert {
    condition     = databricks_policy_info.policy["restrict_region"].on_securable_fullname == "governed"
    error_message = "A catalog policy must use the catalog as its securable full name."
  }

  assert {
    condition     = databricks_policy_info.policy["restrict_region"].when_condition == null
    error_message = "A policy without a table selector must not set a table condition."
  }

  assert {
    condition = (
      length(databricks_policy_info.policy["restrict_region"].match_columns) == 1 &&
      databricks_policy_info.policy["restrict_region"].match_columns[0].alias == "region" &&
      databricks_policy_info.policy["restrict_region"].match_columns[0].condition == "has_tag('region')"
    )
    error_message = "A key-only column selector must use has_tag."
  }

  assert {
    condition = (
      databricks_policy_info.policy["restrict_region"].row_filter.function_name == "governed.security.filter_region" &&
      length(databricks_policy_info.policy["restrict_region"].row_filter.using) == 1 &&
      databricks_policy_info.policy["restrict_region"].row_filter.using[0].alias == "region"
    )
    error_message = "The required column alias must be the row-filter UDF argument."
  }
}

run "schema" {
  command = plan

  variables {
    policies = {
      restrict_tenant = {
        scope = {
          catalog = "governed"
          schema  = "protected"
        }
        principals = {
          include = ["analysts"]
          exclude = ["administrators"]
        }
        table = {
          key   = "sensitivity"
          value = "restricted"
        }
        columns = {
          first = {
            key   = "tenant"
            value = "identifier"
            alias = "tenant"
          }
          second = {
            key   = "region"
            alias = "region"
          }
          third = {
            key   = "status"
            value = "active"
            alias = "status"
          }
        }
        function = "governed.security.filter_tenant"
        comment  = "Restrict protected tenant rows."
      }
    }
  }

  override_module {
    target  = module.validation
    outputs = {}
  }

  assert {
    condition = (
      databricks_policy_info.policy["restrict_tenant"].on_securable_type == "SCHEMA" &&
      databricks_policy_info.policy["restrict_tenant"].on_securable_fullname == "governed.protected"
    )
    error_message = "A scope with schema must create a schema policy using its two-part full name."
  }

  assert {
    condition     = databricks_policy_info.policy["restrict_tenant"].when_condition == "has_tag_value('sensitivity', 'restricted')"
    error_message = "A valued table selector must use has_tag_value."
  }

  assert {
    condition = (
      length(databricks_policy_info.policy["restrict_tenant"].match_columns) == 3 &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[0].alias == "tenant" &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[0].condition == "has_tag_value('tenant', 'identifier')" &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[1].alias == "region" &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[1].condition == "has_tag('region')" &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[2].alias == "status" &&
      databricks_policy_info.policy["restrict_tenant"].match_columns[2].condition == "has_tag_value('status', 'active')"
    )
    error_message = "All three ordered column selectors must use the requested tag predicate."
  }

  assert {
    condition = (
      length(databricks_policy_info.policy["restrict_tenant"].row_filter.using) == 3 &&
      databricks_policy_info.policy["restrict_tenant"].row_filter.using[0].alias == "tenant" &&
      databricks_policy_info.policy["restrict_tenant"].row_filter.using[1].alias == "region" &&
      databricks_policy_info.policy["restrict_tenant"].row_filter.using[2].alias == "status"
    )
    error_message = "Column aliases must be passed to the row-filter UDF in selector order."
  }
}

run "required" {
  command = plan

  variables {
    policies = {
      invalid = {
        scope = { catalog = "governed" }
        principals = {
          include = ["account users"]
        }
        columns  = {}
        function = "governed.security.filter_region"
      }
    }
  }

  expect_failures = [
    var.policies,
  ]
}

run "disabled" {
  command = plan

  variables {
    enabled = false
    policies = {
      ignored = {
        scope = { catalog = "" }
        principals = {
          include = []
        }
        columns = {
          first = {
            key   = ""
            alias = ""
          }
        }
        function = ""
      }
    }
  }

  assert {
    condition     = output.policies == {}
    error_message = "A disabled module must create and validate no policies."
  }
}
