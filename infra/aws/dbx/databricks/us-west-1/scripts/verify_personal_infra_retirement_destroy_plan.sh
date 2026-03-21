#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPROVED_DELETE_ADDRESSES_JSON='[
  "aws_iam_role.cross_account_role",
  "aws_iam_role_policy.cross_account",
  "aws_s3_bucket.root_storage_bucket",
  "aws_s3_bucket_versioning.root_bucket_versioning",
  "aws_s3_bucket_server_side_encryption_configuration.root_storage_bucket_sse_s3",
  "aws_s3_bucket_public_access_block.root_storage_bucket",
  "aws_s3_bucket_policy.root_bucket_policy",
  "module.databricks_mws_workspace.databricks_mws_credentials.this",
  "module.databricks_mws_workspace.databricks_mws_storage_configurations.this",
  "module.databricks_mws_workspace.databricks_mws_workspaces.workspace",
  "module.unity_catalog_metastore_assignment.databricks_metastore_assignment.default_metastore",
  "module.user_assignment.databricks_mws_permission_assignment.workspace_access",
  "module.network_connectivity_configuration.databricks_mws_network_connectivity_config.ncc",
  "module.network_policy.databricks_account_network_policy.restrictive_network_policy",
  "module.log_delivery.aws_s3_bucket.log_delivery",
  "module.log_delivery.aws_s3_bucket_public_access_block.log_delivery",
  "module.log_delivery.aws_s3_bucket_versioning.log_delivery_versioning",
  "module.log_delivery.aws_s3_bucket_policy.log_delivery",
  "module.log_delivery.aws_iam_role.log_delivery",
  "module.log_delivery.databricks_mws_credentials.log_writer",
  "module.log_delivery.databricks_mws_storage_configurations.log_bucket",
  "module.log_delivery.databricks_mws_log_delivery.audit_logs"
]'

if [[ "${1:-}" == "--plan-json" ]]; then
  PLAN_JSON="$(cat "$2")"
else
  PLAN_PATH="$1"
  if [[ "$PLAN_PATH" != /* ]]; then
    PLAN_PATH="$(pwd)/$PLAN_PATH"
  fi
  PLAN_JSON="$(
    DATABRICKS_AUTH_TYPE="${DATABRICKS_AUTH_TYPE:-oauth-m2m}" \
      direnv exec "$ROOT_DIR" terraform -chdir="$ROOT_DIR" show -json "$PLAN_PATH"
  )"
fi

jq -e '[.resource_changes[]? | select(.change.actions == ["delete"])] | length > 0' <<<"$PLAN_JSON" >/dev/null || {
  echo "destroy plan contains no delete actions; refusing to continue" >&2
  exit 1
}

jq -e '
  [.resource_changes[]? | .change.actions]
  | all(. == ["delete"] or . == ["no-op"])
' <<<"$PLAN_JSON" >/dev/null || {
  echo "destroy plan contains create, update, or replace actions; refusing to continue" >&2
  exit 1
}

jq -e '
  [
    .resource_changes[]?
    | select(
        (.address | test("module\\.unity_catalog_metastore_creation\\.databricks_metastore\\.this")) or
        (.type == "databricks_metastore") or
        (.type == "databricks_user") or
        ([.address, (.change.before | tostring)] | join(" ") | test("okta-databricks-users|sandbox"; "i"))
      )
  ] | length == 0
' <<<"$PLAN_JSON" >/dev/null || {
  echo "destroy plan touches preserved shared resources or sandbox markers; refusing to continue" >&2
  exit 1
}

DISALLOWED_DELETE_ADDRESSES="$(
  jq -r --argjson approved_delete_addresses "$APPROVED_DELETE_ADDRESSES_JSON" '
    [
      .resource_changes[]?
      | select(.change.actions == ["delete"])
      | . as $resource_change
      | select(($approved_delete_addresses | index($resource_change.address)) == null)
      | $resource_change.address
    ] | .[]
  ' <<<"$PLAN_JSON"
)"

if [[ -n "$DISALLOWED_DELETE_ADDRESSES" ]]; then
  {
    echo "destroy plan deletes resources outside approved retirement scope; refusing to continue"
    while IFS= read -r address; do
      [[ -n "$address" ]] && echo "- $address"
    done <<<"$DISALLOWED_DELETE_ADDRESSES"
  } >&2
  exit 1
fi

jq -r '
  [
    "Retirement destroy plan review summary:",
    (.resource_changes[]? | select(.change.actions == ["delete"]) | "- " + .address)
  ] | .[]
' <<<"$PLAN_JSON"
