#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--state-json" ]]; then
  STATE_JSON="$(cat "$2")"
else
  STATE_JSON="$(
    DATABRICKS_AUTH_TYPE="${DATABRICKS_AUTH_TYPE:-oauth-m2m}" \
      direnv exec "$ROOT_DIR" terraform -chdir="$ROOT_DIR" state pull
  )"
fi

jq -e '.resources | length > 0' <<<"$STATE_JSON" >/dev/null || {
  echo "retirement state is empty; refusing to inventory an unqualified or wrong backend" >&2
  exit 1
}

jq -e '[.. | strings | select(test("sandbox"; "i"))] | length == 0' <<<"$STATE_JSON" >/dev/null || {
  echo "retirement state contains sandbox markers; refusing to continue" >&2
  exit 1
}

jq -r '
  [
    "# Personal Infra Retirement Inventory",
    "",
    "## Managed Resources",
    (
      .resources[]
      | . as $resource
      | .instances[]
      | "- " +
        (($resource.module // "root")) +
        " :: " +
        $resource.type +
        "." +
        $resource.name +
        " :: " +
        (
          [
            .attributes.id,
            .attributes.bucket,
            .attributes.name,
            .attributes.workspace_id,
            .attributes.workspace_name
          ]
          | map(select(. != null and . != ""))
          | unique
          | join(", ")
        )
    ),
    "",
    "## Manual Adjudication Reminder",
    "- Any live personal-infra object missing from this inventory must stay out of Terraform destroy until ownership is proven."
  ] | .[]
' <<<"$STATE_JSON"
