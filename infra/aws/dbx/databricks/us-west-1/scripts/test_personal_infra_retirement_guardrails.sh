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

cat >"$tmpdir/retirement-state-prod-infra.json" <<'EOF'
{
  "version": 4,
  "terraform_version": "1.10.0",
  "serial": 1,
  "lineage": "prod-infra",
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "root_storage_bucket",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "attributes": {
            "id": "prod-infra-workspace-root-storage",
            "bucket": "prod-infra-workspace-root-storage"
          }
        }
      ]
    }
  ]
}
EOF

if "$SCRIPTS_DIR/render_personal_infra_retirement_inventory.sh" \
  --state-json "$tmpdir/retirement-state-prod-infra.json" \
  >"$tmpdir/prod.out" 2>"$tmpdir/prod.err"; then
  echo "expected non-personal retirement state to fail inventory generation" >&2
  exit 1
fi
rg -q 'retirement state contains no personal-infra ownership markers; refusing to inventory a non-personal backend' "$tmpdir/prod.err"

"$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$TESTDATA_DIR/retirement-plan-delete-only.json" \
  >"$tmpdir/delete-only.out"
rg -q 'Retirement destroy plan review summary:' "$tmpdir/delete-only.out"
rg -q -- '- aws_s3_bucket.root_storage_bucket' "$tmpdir/delete-only.out"
rg -q -- '- module.databricks_mws_workspace.databricks_mws_workspaces.workspace' "$tmpdir/delete-only.out"

cat >"$tmpdir/retirement-plan-approved-expanded-scope.json" <<'EOF'
{
  "format_version": "1.2",
  "resource_changes": [
    {
      "address": "module.network_connectivity_configuration.databricks_mws_network_connectivity_config.ncc",
      "mode": "managed",
      "type": "databricks_mws_network_connectivity_config",
      "name": "ncc",
      "change": {
        "actions": ["delete"],
        "before": {
          "name": "personal-infra-ncc"
        },
        "after": null
      }
    },
    {
      "address": "module.network_policy.databricks_account_network_policy.restrictive_network_policy",
      "mode": "managed",
      "type": "databricks_account_network_policy",
      "name": "restrictive_network_policy",
      "change": {
        "actions": ["delete"],
        "before": {
          "name": "personal-infra-network-policy"
        },
        "after": null
      }
    },
    {
      "address": "module.databricks_mws_workspace.null_resource.previous",
      "mode": "managed",
      "type": "null_resource",
      "name": "previous",
      "change": {
        "actions": ["delete"],
        "before": {
          "id": "123"
        },
        "after": null
      }
    },
    {
      "address": "module.databricks_mws_workspace.time_sleep.wait_30_seconds",
      "mode": "managed",
      "type": "time_sleep",
      "name": "wait_30_seconds",
      "change": {
        "actions": ["delete"],
        "before": {
          "id": "2026-03-20T00:00:00Z"
        },
        "after": null
      }
    },
    {
      "address": "module.log_delivery[0].time_sleep.wait",
      "mode": "managed",
      "type": "time_sleep",
      "name": "wait",
      "change": {
        "actions": ["delete"],
        "before": {
          "id": "2026-03-20T00:00:10Z"
        },
        "after": null
      }
    },
    {
      "address": "module.log_delivery[0].databricks_mws_log_delivery.audit_logs",
      "mode": "managed",
      "type": "databricks_mws_log_delivery",
      "name": "audit_logs",
      "change": {
        "actions": ["delete"],
        "before": {
          "log_delivery_status": "ENABLED",
          "storage_configuration_id": "personal-infra-log-bucket"
        },
        "after": null
      }
    }
  ]
}
EOF

"$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$tmpdir/retirement-plan-approved-expanded-scope.json" \
  >"$tmpdir/approved-expanded-scope.out"
rg -q -- '- module.network_connectivity_configuration.databricks_mws_network_connectivity_config.ncc' "$tmpdir/approved-expanded-scope.out"
rg -q -- '- module.network_policy.databricks_account_network_policy.restrictive_network_policy' "$tmpdir/approved-expanded-scope.out"
rg -F -q -- '- module.databricks_mws_workspace.null_resource.previous' "$tmpdir/approved-expanded-scope.out"
rg -F -q -- '- module.databricks_mws_workspace.time_sleep.wait_30_seconds' "$tmpdir/approved-expanded-scope.out"
rg -F -q -- '- module.log_delivery[0].time_sleep.wait' "$tmpdir/approved-expanded-scope.out"
rg -F -q -- '- module.log_delivery[0].databricks_mws_log_delivery.audit_logs' "$tmpdir/approved-expanded-scope.out"

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

cat >"$tmpdir/retirement-plan-out-of-scope-group.json" <<'EOF'
{
  "format_version": "1.2",
  "resource_changes": [
    {
      "address": "databricks_group.platform_admins",
      "mode": "managed",
      "type": "databricks_group",
      "name": "platform_admins",
      "change": {
        "actions": ["delete"],
        "before": {
          "display_name": "platform_admins"
        },
        "after": null
      }
    }
  ]
}
EOF

if "$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$tmpdir/retirement-plan-out-of-scope-group.json" \
  >"$tmpdir/retirement-plan-out-of-scope-group.out" 2>"$tmpdir/retirement-plan-out-of-scope-group.err"; then
  echo "expected destroy-plan verifier to reject out-of-scope shared-group delete fixture" >&2
  exit 1
fi
rg -q 'destroy plan deletes resources outside approved retirement scope; refusing to continue' "$tmpdir/retirement-plan-out-of-scope-group.err"
rg -q 'databricks_group.platform_admins' "$tmpdir/retirement-plan-out-of-scope-group.err"
