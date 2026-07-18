output "policies" {
  description = "Managed ABAC row-filter policies keyed by policy name."
  value = {
    for name, policy in databricks_policy_info.policy : name => {
      id     = policy.id
      name   = policy.name
      type   = policy.policy_type
      target = policy.for_securable_type
      scope = {
        type = policy.on_securable_type
        name = policy.on_securable_fullname
      }
    }
  }
}
