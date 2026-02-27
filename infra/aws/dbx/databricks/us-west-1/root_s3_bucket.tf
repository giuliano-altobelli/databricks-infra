# EXPLANATION: Create the workspace root bucket

resource "aws_s3_bucket" "root_storage_bucket" {
  count         = local.create_workspace ? 1 : 0
  bucket        = "${var.resource_prefix}-workspace-root-storage"
  force_destroy = true
  tags = {
    Name    = "${var.resource_prefix}-workspace-root-storage"
    Project = var.resource_prefix
  }
}

resource "aws_s3_bucket_versioning" "root_bucket_versioning" {
  count  = local.create_workspace ? 1 : 0
  bucket = aws_s3_bucket.root_storage_bucket[0].id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_bucket_kms" {
  count  = local.create_workspace && local.enable_customer_managed_keys ? 1 : 0
  bucket = aws_s3_bucket.root_storage_bucket[0].bucket
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.workspace_storage[0].arn
    }
  }
  depends_on = [aws_kms_alias.workspace_storage_key_alias]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_bucket_sse_s3" {
  count  = local.create_workspace && !local.enable_customer_managed_keys ? 1 : 0
  bucket = aws_s3_bucket.root_storage_bucket[0].bucket
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "root_storage_bucket" {
  count                   = local.create_workspace ? 1 : 0
  bucket                  = aws_s3_bucket.root_storage_bucket[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.root_storage_bucket]
}

data "databricks_aws_bucket_policy" "this" {
  count                    = local.create_workspace ? 1 : 0
  databricks_e2_account_id = var.databricks_account_id
  aws_partition            = local.assume_role_partition
  bucket                   = aws_s3_bucket.root_storage_bucket[0].bucket
}

resource "aws_s3_bucket_policy" "root_bucket_policy" {
  count      = local.create_workspace ? 1 : 0
  bucket     = aws_s3_bucket.root_storage_bucket[0].id
  policy     = data.databricks_aws_bucket_policy.this[0].json
  depends_on = [aws_s3_bucket_public_access_block.root_storage_bucket]

  lifecycle {
    ignore_changes = [policy]
  }
}
