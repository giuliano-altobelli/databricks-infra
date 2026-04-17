locals {
  enabled_service_principals = var.enabled ? var.service_principals : {}

  placeholder_secret_string = jsonencode({
    client_secret  = ""
    client_id      = ""
    application_id = ""
  })
}

resource "aws_secretsmanager_secret" "service_principal" {
  for_each = local.enabled_service_principals

  name        = "${var.name_prefix}/${each.key}"
  description = "Databricks service principal credential placeholder."
}

resource "aws_secretsmanager_secret_version" "placeholder" {
  for_each = local.enabled_service_principals

  secret_id     = aws_secretsmanager_secret.service_principal[each.key].id
  secret_string = local.placeholder_secret_string

  lifecycle {
    ignore_changes = [secret_string]
  }
}
