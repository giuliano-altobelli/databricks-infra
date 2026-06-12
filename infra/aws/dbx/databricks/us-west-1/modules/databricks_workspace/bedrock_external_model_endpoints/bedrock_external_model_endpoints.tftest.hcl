mock_provider "databricks" {}

run "single_model_endpoint_shape" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      primary = {
        name                 = "bedrock-primary"
        aws_region           = "us-west-2"
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
        served_entities = {
          claude = {
            name               = "claude_sonnet"
            task               = "llm/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 100
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
          {
            principal_type = "group"
            principal_name = "ai-query-users"
          },
        ]
      }
    }
  }

  assert {
    condition     = databricks_model_serving.this["primary"].config[0].served_entities[0].external_model[0].provider == "amazon-bedrock"
    error_message = "External model provider must be fixed to amazon-bedrock."
  }

  assert {
    condition     = databricks_model_serving.this["primary"].config[0].served_entities[0].external_model[0].amazon_bedrock_config[0].instance_profile_arn == "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
    error_message = "Endpoint-level instance_profile_arn must be passed through to the Bedrock config."
  }

  assert {
    condition     = databricks_model_serving.this["primary"].config[0].traffic_config[0].routes[0].served_entity_name == "claude_sonnet"
    error_message = "Traffic routes must target the served entity name."
  }

  assert {
    condition = contains([
      for acl in databricks_permissions.serving_endpoint["primary"].access_control : acl.permission_level
      if acl.group_name == "ai-query-users"
    ], "CAN_QUERY")
    error_message = "Endpoint permission_level must default to CAN_QUERY when omitted."
  }
}

run "multi_model_endpoint_shape" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      shared = {
        name                 = "bedrock-shared"
        aws_region           = "us-west-2"
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
        served_entities = {
          claude = {
            name               = "claude_sonnet"
            task               = "llm/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 90
          }
          titan = {
            name               = "amazon_titan"
            task               = "llm/v1/chat"
            bedrock_provider   = "Amazon"
            bedrock_model      = "amazon.titan-text-premier-v1:0"
            traffic_percentage = 10
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
          {
            principal_type   = "service_principal"
            principal_name   = "00000000-0000-0000-0000-000000000000"
            permission_level = "CAN_QUERY"
          },
        ]
      }
    }
  }

  assert {
    condition     = length(databricks_model_serving.this["shared"].config[0].served_entities) == 2
    error_message = "The module must support multiple Bedrock external served entities in one endpoint."
  }

  assert {
    condition     = length(databricks_model_serving.this["shared"].config[0].traffic_config[0].routes) == 2
    error_message = "A multi-model endpoint must emit one traffic route per served entity."
  }

  assert {
    condition     = output.served_entity_names["shared"]["claude"] == "claude_sonnet"
    error_message = "served_entity_names output must preserve caller-defined served entity keys."
  }
}

run "disabled_outputs_empty" {
  command = plan

  variables {
    enabled = false
    bedrock_external_model_endpoints = {
      ignored = {
        name                 = ""
        aws_region           = ""
        instance_profile_arn = ""
        served_entities      = {}
        permissions          = []
      }
    }
  }

  assert {
    condition     = length(output.endpoint_ids) == 0
    error_message = "endpoint_ids must be empty when the module is disabled."
  }

  assert {
    condition     = length(output.served_entity_names) == 0
    error_message = "served_entity_names must be empty when the module is disabled."
  }
}

run "reject_mixed_tasks" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      mixed = {
        name                 = "bedrock-mixed"
        aws_region           = "us-west-2"
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
        served_entities = {
          first = {
            name               = "first"
            task               = "llm/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 50
          }
          second = {
            name               = "second"
            task               = "llm/v1/completions"
            bedrock_provider   = "Amazon"
            bedrock_model      = "amazon.titan-text-premier-v1:0"
            traffic_percentage = 50
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
        ]
      }
    }
  }

  expect_failures = [
    var.bedrock_external_model_endpoints,
  ]
}

run "reject_traffic_not_100" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      invalid = {
        name                 = "bedrock-invalid"
        aws_region           = "us-west-2"
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
        served_entities = {
          first = {
            name               = "first"
            task               = "llm/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 40
          }
          second = {
            name               = "second"
            task               = "llm/v1/chat"
            bedrock_provider   = "Amazon"
            bedrock_model      = "amazon.titan-text-premier-v1:0"
            traffic_percentage = 40
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
        ]
      }
    }
  }

  expect_failures = [
    var.bedrock_external_model_endpoints,
  ]
}

run "reject_unsupported_task" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      invalid = {
        name                 = "bedrock-invalid-task"
        aws_region           = "us-west-2"
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"
        served_entities = {
          first = {
            name               = "first"
            task               = "agent/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 100
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
        ]
      }
    }
  }

  expect_failures = [
    var.bedrock_external_model_endpoints,
  ]
}

run "reject_malformed_instance_profile_arn" {
  command = plan

  variables {
    bedrock_external_model_endpoints = {
      invalid = {
        name                 = "bedrock-invalid-instance-profile"
        aws_region           = "us-west-2"
        instance_profile_arn = "not-an-instance-profile-arn"
        served_entities = {
          first = {
            name               = "first"
            task               = "llm/v1/chat"
            bedrock_provider   = "Anthropic"
            bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
            traffic_percentage = 100
          }
        }
        permissions = [
          {
            principal_type   = "group"
            principal_name   = "platform-admins"
            permission_level = "CAN_MANAGE"
          },
        ]
      }
    }
  }

  expect_failures = [
    var.bedrock_external_model_endpoints,
  ]
}
