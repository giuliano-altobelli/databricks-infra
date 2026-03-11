output "policy_ids" {
  description = "Map of stable policy keys to Databricks cluster policy IDs."
  value = {
    for policy_key, resource in databricks_cluster_policy.this :
    policy_key => resource.id
  }
}
