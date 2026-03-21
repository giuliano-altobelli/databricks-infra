#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

jq -r '
  [
    "Retirement destroy plan review summary:",
    (.resource_changes[]? | select(.change.actions == ["delete"]) | "- " + .address)
  ] | .[]
' <<<"$PLAN_JSON"
