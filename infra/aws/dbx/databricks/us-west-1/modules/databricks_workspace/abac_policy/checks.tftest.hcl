run "key" {
  command = plan

  module {
    source = "./validation"
  }

  variables {
    policies = {
      restrict_region = {
        tags = [{
          key     = "region"
          actual  = "region"
          allowed = []
        }]
        function = {
          name      = "governed.security.filter_region"
          available = ["governed.security.filter_region"]
        }
      }
    }
  }

  assert {
    condition     = length(output.policies) == 1 && contains(output.policies, "restrict_region")
    error_message = "A key-only tag must not require an allowed value."
  }
}

run "values" {
  command = plan

  module {
    source = "./validation"
  }

  variables {
    policies = {
      restrict_tenant = {
        tags = [
          {
            key     = "sensitivity"
            actual  = "sensitivity"
            value   = "restricted"
            allowed = ["public", "restricted"]
          },
          {
            key     = "tenant"
            actual  = "tenant"
            value   = "identifier"
            allowed = ["identifier"]
          },
          {
            key     = "region"
            actual  = "region"
            allowed = []
          },
        ]
        function = {
          name      = "governed.security.filter_tenant"
          available = ["governed.security.filter_tenant"]
        }
      }
    }
  }
}

run "tag" {
  command = plan

  module {
    source = "./validation"
  }

  variables {
    policies = {
      restrict_region = {
        tags = [{
          key     = "region"
          actual  = "other"
          allowed = []
        }]
        function = {
          name      = "governed.security.filter_region"
          available = ["governed.security.filter_region"]
        }
      }
    }
  }

  expect_failures = [
    terraform_data.policy["restrict_region"],
  ]
}

run "value" {
  command = plan

  module {
    source = "./validation"
  }

  variables {
    policies = {
      restrict_region = {
        tags = [{
          key     = "region"
          actual  = "region"
          value   = "west"
          allowed = ["east"]
        }]
        function = {
          name      = "governed.security.filter_region"
          available = ["governed.security.filter_region"]
        }
      }
    }
  }

  expect_failures = [
    terraform_data.policy["restrict_region"],
  ]
}

run "function" {
  command = plan

  module {
    source = "./validation"
  }

  variables {
    policies = {
      restrict_region = {
        tags = [{
          key     = "region"
          actual  = "region"
          allowed = []
        }]
        function = {
          name      = "governed.security.filter_region"
          available = ["governed.security.other"]
        }
      }
    }
  }

  expect_failures = [
    terraform_data.policy["restrict_region"],
  ]
}
