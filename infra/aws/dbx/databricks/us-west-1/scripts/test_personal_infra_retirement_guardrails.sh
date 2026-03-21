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

if "$SCRIPTS_DIR/render_personal_infra_retirement_inventory.sh" \
  --state-json "$TESTDATA_DIR/retirement-state-sandbox-contamination.json" \
  >"$tmpdir/sandbox.out" 2>"$tmpdir/sandbox.err"; then
  echo "expected sandbox-contaminated retirement state to fail inventory generation" >&2
  exit 1
fi
