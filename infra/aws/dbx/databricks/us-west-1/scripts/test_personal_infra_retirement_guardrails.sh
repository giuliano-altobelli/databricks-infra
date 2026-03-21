#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
TESTDATA_DIR="$SCRIPTS_DIR/testdata"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

"$SCRIPTS_DIR/render_personal_infra_retirement_inventory.sh" \
  --state-json "$TESTDATA_DIR/retirement-state-populated.json" \
  >"$tmpdir/inventory.md"

rg -q 'personal-infra' "$tmpdir/inventory.md"
rg -q 'module.databricks_mws_workspace' "$tmpdir/inventory.md"

if "$SCRIPTS_DIR/render_personal_infra_retirement_inventory.sh" \
  --state-json "$TESTDATA_DIR/retirement-state-empty.json" \
  >"$tmpdir/empty.out" 2>"$tmpdir/empty.err"; then
  echo "expected empty retirement state to fail inventory generation" >&2
  exit 1
fi
rg -q 'retirement state is empty; refusing to inventory an unqualified or wrong backend' "$tmpdir/empty.err"

if "$SCRIPTS_DIR/render_personal_infra_retirement_inventory.sh" \
  --state-json "$TESTDATA_DIR/retirement-state-sandbox-contamination.json" \
  >"$tmpdir/sandbox.out" 2>"$tmpdir/sandbox.err"; then
  echo "expected sandbox-contaminated retirement state to fail inventory generation" >&2
  exit 1
fi
rg -q 'retirement state contains sandbox markers; refusing to continue' "$tmpdir/sandbox.err"

"$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$TESTDATA_DIR/retirement-plan-delete-only.json" \
  >"$tmpdir/delete-only.out"
rg -q 'Retirement destroy plan review summary:' "$tmpdir/delete-only.out"
rg -q -- '- aws_s3_bucket.root_storage_bucket' "$tmpdir/delete-only.out"
rg -q -- '- module.databricks_mws_workspace.databricks_mws_workspaces.workspace' "$tmpdir/delete-only.out"

for fixture in \
  retirement-plan-empty.json \
  retirement-plan-mixed-actions.json \
  retirement-plan-forbidden-metastore.json \
  retirement-plan-sandbox-contamination.json
do
  if "$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
    --plan-json "$TESTDATA_DIR/$fixture" \
    >"$tmpdir/$fixture.out" 2>"$tmpdir/$fixture.err"; then
    echo "expected destroy-plan verifier to reject $fixture" >&2
    exit 1
  fi
  case "$fixture" in
    retirement-plan-empty.json)
      rg -q 'destroy plan contains no delete actions; refusing to continue' "$tmpdir/$fixture.err"
      ;;
    retirement-plan-mixed-actions.json)
      rg -q 'destroy plan contains create, update, or replace actions; refusing to continue' "$tmpdir/$fixture.err"
      ;;
    retirement-plan-forbidden-metastore.json|retirement-plan-sandbox-contamination.json)
      rg -q 'destroy plan touches preserved shared resources or sandbox markers; refusing to continue' "$tmpdir/$fixture.err"
      ;;
  esac
done

cat >"$tmpdir/retirement-plan-forbidden-user.json" <<'EOF'
{
  "format_version": "1.2",
  "resource_changes": [
    {
      "address": "databricks_user.this",
      "mode": "managed",
      "type": "databricks_user",
      "name": "this",
      "change": {
        "actions": ["delete"],
        "before": {
          "user_name": "person@example.com"
        },
        "after": null
      }
    }
  ]
}
EOF

if "$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$tmpdir/retirement-plan-forbidden-user.json" \
  >"$tmpdir/retirement-plan-forbidden-user.out" 2>"$tmpdir/retirement-plan-forbidden-user.err"; then
  echo "expected destroy-plan verifier to reject databricks_user delete fixture" >&2
  exit 1
fi
rg -q 'destroy plan touches preserved shared resources or sandbox markers; refusing to continue' "$tmpdir/retirement-plan-forbidden-user.err"

cat >"$tmpdir/retirement-plan-forbidden-okta-group.json" <<'EOF'
{
  "format_version": "1.2",
  "resource_changes": [
    {
      "address": "databricks_group.okta_databricks_users",
      "mode": "managed",
      "type": "databricks_group",
      "name": "okta_databricks_users",
      "change": {
        "actions": ["delete"],
        "before": {
          "display_name": "okta-databricks-users"
        },
        "after": null
      }
    }
  ]
}
EOF

if "$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$tmpdir/retirement-plan-forbidden-okta-group.json" \
  >"$tmpdir/retirement-plan-forbidden-okta-group.out" 2>"$tmpdir/retirement-plan-forbidden-okta-group.err"; then
  echo "expected destroy-plan verifier to reject okta-databricks-users fixture" >&2
  exit 1
fi
rg -q 'destroy plan touches preserved shared resources or sandbox markers; refusing to continue' "$tmpdir/retirement-plan-forbidden-okta-group.err"
