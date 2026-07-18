output "policies" {
  description = "Validated policy names."
  value       = toset(keys(terraform_data.policy))
}
