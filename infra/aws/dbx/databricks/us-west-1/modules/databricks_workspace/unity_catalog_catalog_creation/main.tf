locals {
  enabled_catalog         = var.enabled
  aws_safe_catalog_suffix = replace(var.catalog_name, "_", "-")
  normalized_catalog_reader_principals = [
    for principal in var.catalog_reader_principals : trimspace(principal)
  ]

  # Preserve the existing isolated resource names when the legacy caller maps
  # its old workspace-scoped naming formula into the new interface.
  legacy_name_compat = var.catalog_name == replace("${var.resource_prefix}-catalog-${var.workspace_id}", "-", "_")
  resource_name_base = local.legacy_name_compat ? local.aws_safe_catalog_suffix : "${var.resource_prefix}-${local.aws_safe_catalog_suffix}-${var.workspace_id}"

  uc_iam_role             = local.resource_name_base
  catalog_bucket_name     = local.resource_name_base
  storage_credential_name = "${local.resource_name_base}-storage-credential"
  external_location_name  = "${local.resource_name_base}-external-location"
  iam_policy_name         = local.legacy_name_compat ? "${var.resource_prefix}-catalog-policy-${var.workspace_id}" : "${local.resource_name_base}-policy"
  kms_key_name            = local.legacy_name_compat ? "${var.resource_prefix}-catalog-storage-${var.workspace_id}-key" : "${local.resource_name_base}-storage-key"
  kms_key_alias_name      = "alias/${local.kms_key_name}"

  normalized_additional_catalog_workspace_ids = [
    for workspace_id in var.workspace_ids : trimspace(workspace_id)
  ]

  normalized_catalog_workspace_ids = concat(
    [trimspace(var.workspace_id)],
    local.normalized_additional_catalog_workspace_ids,
  )

  raw_catalog_workspace_binding_keys = [
    for workspace_id in local.normalized_catalog_workspace_ids : workspace_id
  ]

  duplicate_catalog_workspace_binding_keys = toset([
    for key in local.raw_catalog_workspace_binding_keys : key
    if length([
      for seen in local.raw_catalog_workspace_binding_keys : seen if seen == key
    ]) > 1
  ])

  # Databricks already binds isolated securables to the creating workspace.
  # Managing that same binding explicitly breaks destroy ordering because the
  # workspace-scoped provider loses visibility before Terraform can delete the
  # securable itself.
  catalog_workspace_bindings = {
    for workspace_id in distinct(local.normalized_additional_catalog_workspace_ids) :
    "additional:${workspace_id}" => {
      workspace_id = workspace_id
    }
  }
}

resource "null_resource" "previous" {
  count = var.enabled ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.enabled || trimspace(var.catalog_name) != ""
      error_message = "catalog_name must be non-empty when enabled is true."
    }

    precondition {
      condition     = !var.enabled || trimspace(var.catalog_admin_principal) != ""
      error_message = "catalog_admin_principal must be non-empty when enabled is true."
    }

    precondition {
      condition = !var.enabled || (
        length(local.catalog_bucket_name) >= 3 &&
        length(local.catalog_bucket_name) <= 63 &&
        can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", local.catalog_bucket_name))
      )
      error_message = "The generated S3 bucket name must be 3-63 characters, lowercase alphanumeric or hyphen, and start and end with an alphanumeric character."
    }

    precondition {
      condition     = !var.enabled || length(var.catalog_name) <= 255
      error_message = "catalog_name must be 255 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.storage_credential_name) <= 255
      error_message = "The generated storage credential name must be 255 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.external_location_name) <= 255
      error_message = "The generated external location name must be 255 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.uc_iam_role) <= 64
      error_message = "The generated IAM role name must be 64 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.iam_policy_name) <= 128
      error_message = "The generated IAM policy name must be 128 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.kms_key_alias_name) <= 256
      error_message = "The generated KMS alias name must be 256 characters or fewer."
    }

    precondition {
      condition     = !var.enabled || length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

# Wait to prevent race condition between IAM role and external location validation.
resource "time_sleep" "wait_60_seconds" {
  count           = var.enabled ? 1 : 0
  depends_on      = [null_resource.previous]
  create_duration = "60s"
}

resource "aws_kms_key" "catalog_storage" {
  count       = var.enabled ? 1 : 0
  description = "KMS key for Databricks catalog storage ${var.catalog_name}"
  policy = jsonencode({
    Version : "2012-10-17",
    Id : "key-policy-catalog-storage-${var.workspace_id}",
    Statement : [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : [var.cmk_admin_arn]
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "Allow IAM Role to use the key",
        Effect : "Allow",
        Principal : {
          AWS : "arn:${var.aws_iam_partition}:iam::${var.aws_account_id}:role/${local.uc_iam_role}"
        },
        Action : [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ],
        Resource : "*"
      }
    ]
  })
  tags = {
    Name    = local.kms_key_name
    Project = var.resource_prefix
  }
}

resource "aws_kms_alias" "catalog_storage_key_alias" {
  count         = var.enabled ? 1 : 0
  name          = local.kms_key_alias_name
  target_key_id = aws_kms_key.catalog_storage[0].id
}

# Storage Credential (created before role): Databricks emits the trust values
# needed to construct the AWS assume-role policy for the same apply.
resource "databricks_storage_credential" "workspace_catalog_storage_credential" {
  count = var.enabled ? 1 : 0
  name  = local.storage_credential_name

  aws_iam_role {
    role_arn = "arn:${var.aws_iam_partition}:iam::${var.aws_account_id}:role/${local.uc_iam_role}"
  }

  isolation_mode = "ISOLATION_MODE_ISOLATED"

  lifecycle {
    precondition {
      condition     = !var.enabled || length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "unity_catalog" {
  count                 = var.enabled ? 1 : 0
  aws_account_id        = var.aws_account_id
  aws_partition         = var.aws_assume_partition
  role_name             = local.uc_iam_role
  unity_catalog_iam_arn = var.unity_catalog_iam_arn
  external_id           = databricks_storage_credential.workspace_catalog_storage_credential[0].aws_iam_role[0].external_id
}

data "databricks_aws_unity_catalog_policy" "unity_catalog" {
  count          = var.enabled ? 1 : 0
  aws_account_id = var.aws_account_id
  aws_partition  = var.aws_assume_partition
  bucket_name    = local.catalog_bucket_name
  role_name      = local.uc_iam_role
  kms_name       = aws_kms_alias.catalog_storage_key_alias[0].arn
}

resource "aws_iam_policy" "unity_catalog" {
  count  = var.enabled ? 1 : 0
  name   = local.iam_policy_name
  policy = data.databricks_aws_unity_catalog_policy.unity_catalog[0].json
}

resource "aws_iam_role" "unity_catalog" {
  count              = var.enabled ? 1 : 0
  name               = local.uc_iam_role
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.unity_catalog[0].json
  tags = {
    Name    = local.uc_iam_role
    Project = var.resource_prefix
  }
}

resource "aws_iam_role_policy_attachment" "unity_catalog_attach" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.unity_catalog[0].name
  policy_arn = aws_iam_policy.unity_catalog[0].arn
}

resource "aws_s3_bucket" "unity_catalog_bucket" {
  count         = var.enabled ? 1 : 0
  bucket        = local.catalog_bucket_name
  force_destroy = true
  tags = {
    Name    = local.catalog_bucket_name
    Project = var.resource_prefix
  }
}

resource "aws_s3_bucket_versioning" "unity_catalog_versioning" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.unity_catalog_bucket[0].id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unity_catalog" {
  count  = var.enabled ? 1 : 0
  bucket = aws_s3_bucket.unity_catalog_bucket[0].bucket

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.catalog_storage[0].arn
    }
  }

  depends_on = [aws_kms_alias.catalog_storage_key_alias]
}

resource "aws_s3_bucket_public_access_block" "unity_catalog" {
  count                   = var.enabled ? 1 : 0
  bucket                  = aws_s3_bucket.unity_catalog_bucket[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket.unity_catalog_bucket]
}

resource "databricks_external_location" "workspace_catalog_external_location" {
  count           = var.enabled ? 1 : 0
  name            = local.external_location_name
  url             = "s3://${local.catalog_bucket_name}/"
  credential_name = databricks_storage_credential.workspace_catalog_storage_credential[0].name
  comment         = "External location for catalog ${var.catalog_name}"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"

  depends_on = [
    aws_iam_role_policy_attachment.unity_catalog_attach,
    time_sleep.wait_60_seconds,
  ]

  lifecycle {
    precondition {
      condition     = !var.enabled || length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

resource "databricks_catalog" "workspace_catalog" {
  count          = var.enabled ? 1 : 0
  name           = var.catalog_name
  comment        = "Catalog for workspace ${var.workspace_id}"
  isolation_mode = "ISOLATED"
  storage_root   = "s3://${local.catalog_bucket_name}/"

  properties = {
    purpose = "Catalog for workspace ${var.workspace_id}"
  }

  depends_on = [databricks_external_location.workspace_catalog_external_location]

  lifecycle {
    precondition {
      condition     = !var.enabled || length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "workspace_catalog_storage_credential" {
  for_each = var.enabled ? local.catalog_workspace_bindings : {}

  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.workspace_catalog_storage_credential[0].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "workspace_catalog_external_location" {
  for_each = var.enabled ? local.catalog_workspace_bindings : {}

  securable_type = "external_location"
  securable_name = databricks_external_location.workspace_catalog_external_location[0].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "workspace_catalog" {
  for_each = var.enabled ? local.catalog_workspace_bindings : {}

  securable_type = "catalog"
  securable_name = databricks_catalog.workspace_catalog[0].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_catalog_workspace_binding_keys) == 0
      error_message = "Duplicate workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_catalog_workspace_binding_keys)))}"
    }
  }
}

resource "databricks_default_namespace_setting" "this" {
  count = var.enabled && var.set_default_namespace ? 1 : 0

  namespace {
    value = databricks_catalog.workspace_catalog[0].name
  }

  depends_on = [
    databricks_workspace_binding.workspace_catalog,
    databricks_grant.workspace_catalog,
  ]
}

resource "databricks_grant" "workspace_catalog" {
  count   = var.enabled && var.set_default_namespace ? 1 : 0
  catalog = databricks_catalog.workspace_catalog[0].name

  principal  = var.catalog_admin_principal
  privileges = ["ALL_PRIVILEGES"]

  depends_on = [databricks_workspace_binding.workspace_catalog]
}

resource "databricks_grants" "workspace_catalog" {
  count   = var.enabled && !var.set_default_namespace ? 1 : 0
  catalog = databricks_catalog.workspace_catalog[0].name

  grant {
    principal  = var.catalog_admin_principal
    privileges = ["ALL_PRIVILEGES"]
  }

  dynamic "grant" {
    for_each = local.normalized_catalog_reader_principals

    content {
      principal  = grant.value
      privileges = ["USE_CATALOG"]
    }
  }

  depends_on = [databricks_workspace_binding.workspace_catalog]
}

moved {
  from = null_resource.previous
  to   = null_resource.previous[0]
}

moved {
  from = time_sleep.wait_60_seconds
  to   = time_sleep.wait_60_seconds[0]
}

moved {
  from = aws_kms_key.catalog_storage
  to   = aws_kms_key.catalog_storage[0]
}

moved {
  from = aws_kms_alias.catalog_storage_key_alias
  to   = aws_kms_alias.catalog_storage_key_alias[0]
}

moved {
  from = databricks_storage_credential.workspace_catalog_storage_credential
  to   = databricks_storage_credential.workspace_catalog_storage_credential[0]
}

moved {
  from = aws_iam_policy.unity_catalog
  to   = aws_iam_policy.unity_catalog[0]
}

moved {
  from = aws_iam_role.unity_catalog
  to   = aws_iam_role.unity_catalog[0]
}

removed {
  from = aws_iam_policy_attachment.unity_catalog_attach

  lifecycle {
    destroy = false
  }
}

moved {
  from = aws_s3_bucket.unity_catalog_bucket
  to   = aws_s3_bucket.unity_catalog_bucket[0]
}

moved {
  from = aws_s3_bucket_versioning.unity_catalog_versioning
  to   = aws_s3_bucket_versioning.unity_catalog_versioning[0]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.unity_catalog
  to   = aws_s3_bucket_server_side_encryption_configuration.unity_catalog[0]
}

moved {
  from = aws_s3_bucket_public_access_block.unity_catalog
  to   = aws_s3_bucket_public_access_block.unity_catalog[0]
}

moved {
  from = databricks_external_location.workspace_catalog_external_location
  to   = databricks_external_location.workspace_catalog_external_location[0]
}

moved {
  from = databricks_catalog.workspace_catalog
  to   = databricks_catalog.workspace_catalog[0]
}

moved {
  from = databricks_default_namespace_setting.this
  to   = databricks_default_namespace_setting.this[0]
}

moved {
  from = databricks_grant.workspace_catalog
  to   = databricks_grant.workspace_catalog[0]
}
