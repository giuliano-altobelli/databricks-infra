mock_provider "databricks" {}

run "keyonly" {
  command = plan

  variables {
    tags = {
      isPii = {
        description = " * key-only / description "
      }
    }
  }

  assert {
    condition     = databricks_tag_policy.tag["isPii"].tag_key == "isPii"
    error_message = "A key-only governed tag must preserve its exact key."
  }

  assert {
    condition     = databricks_tag_policy.tag["isPii"].description == " * key-only / description "
    error_message = "A governed tag must preserve its description."
  }

  assert {
    condition     = length(databricks_tag_policy.tag["isPii"].values) == 0
    error_message = "A governed tag without configured values must have an empty allowed-value list."
  }
}

run "valued" {
  command = plan

  variables {
    tags = {
      "Department🚀" = {
        description = "Primary department"
        values      = ["zürich✅", "Engineering", "alpha"]
      }
      "department🚀" = {
        description = "Secondary department"
        values      = ["engineering", "Alpha"]
      }
    }
  }

  assert {
    condition = (
      contains(keys(output.tags), "Department🚀") &&
      contains(keys(output.tags), "department🚀")
    )
    error_message = "Governed tag keys that differ by case must remain distinct."
  }

  assert {
    condition = [
      for value in databricks_tag_policy.tag["Department🚀"].values : value.name
    ] == ["Engineering", "alpha", "zürich✅"]
    error_message = "Allowed values must preserve case and use deterministic ordering."
  }

  assert {
    condition = [
      for value in databricks_tag_policy.tag["department🚀"].values : value.name
    ] == ["Alpha", "engineering"]
    error_message = "Allowed values that differ by case must remain distinct."
  }
}

run "boundary" {
  command = plan

  variables {
    tags = {
      (join("", [for number in range(256) : "a"])) = {
        description = "Maximum-length key"
        values      = [join("", [for number in range(256) : "b"])]
      }
    }
  }

  assert {
    condition     = length(one(values(databricks_tag_policy.tag)).tag_key) == 256
    error_message = "A 256-character governed tag key must be accepted."
  }

  assert {
    condition     = length(one(one(values(databricks_tag_policy.tag)).values).name) == 256
    error_message = "A 256-character governed tag value must be accepted."
  }
}

run "length" {
  command = plan

  variables {
    tags = {
      valid = {
        description = "Invalid value length"
        values      = [join("", [for number in range(257) : "a"])]
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["valid"],
  ]
}

run "empty" {
  command = plan

  variables {
    tags = {
      "" = {
        description = "Empty key"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag[""],
  ]
}

run "description" {
  command = plan

  variables {
    tags = {
      valid = {
        description = "   "
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["valid"],
  ]
}

run "leading" {
  command = plan

  variables {
    tags = {
      valid = {
        description = "Leading whitespace"
        values      = [" invalid"]
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["valid"],
  ]
}

run "trailing" {
  command = plan

  variables {
    tags = {
      "invalid " = {
        description = "Trailing whitespace"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid "],
  ]
}

run "control" {
  command = plan

  variables {
    tags = {
      valid = {
        description = "Control character"
        values      = ["invalid\u0001"]
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["valid"],
  ]
}

run "asterisk" {
  command = plan

  variables {
    tags = {
      "invalid*" = {
        description = "Asterisk"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid*"],
  ]
}

run "period" {
  command = plan

  variables {
    tags = {
      "invalid." = {
        description = "Period"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid."],
  ]
}

run "slash" {
  command = plan

  variables {
    tags = {
      "invalid/" = {
        description = "Slash"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid/"],
  ]
}

run "less" {
  command = plan

  variables {
    tags = {
      "invalid<" = {
        description = "Less than"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid<"],
  ]
}

run "greater" {
  command = plan

  variables {
    tags = {
      "invalid>" = {
        description = "Greater than"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid>"],
  ]
}

run "percent" {
  command = plan

  variables {
    tags = {
      "invalid%" = {
        description = "Percent"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid%"],
  ]
}

run "ampersand" {
  command = plan

  variables {
    tags = {
      "invalid&" = {
        description = "Ampersand"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid&"],
  ]
}

run "question" {
  command = plan

  variables {
    tags = {
      "invalid?" = {
        description = "Question mark"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid?"],
  ]
}

run "backslash" {
  command = plan

  variables {
    tags = {
      "invalid\\" = {
        description = "Backslash"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid\\"],
  ]
}

run "equals" {
  command = plan

  variables {
    tags = {
      "invalid=" = {
        description = "Equals"
      }
    }
  }

  expect_failures = [
    databricks_tag_policy.tag["invalid="],
  ]
}

run "disabled" {
  command = plan

  variables {
    enabled = false
    tags = {
      "invalid*" = {
        description = ""
        values      = [" invalid"]
      }
    }
  }

  assert {
    condition     = output.tags == {}
    error_message = "A disabled module must create and validate no governed tags."
  }
}
