output "arns" {
  value = { for principal_key, secret in aws_secretsmanager_secret.service_principal : principal_key => secret.arn }
}

output "names" {
  value = { for principal_key, secret in aws_secretsmanager_secret.service_principal : principal_key => secret.name }
}

output "version_ids" {
  value = { for principal_key, version in aws_secretsmanager_secret_version.placeholder : principal_key => version.version_id }
}
