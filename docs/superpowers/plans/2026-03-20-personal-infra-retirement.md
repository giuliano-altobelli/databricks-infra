# Personal Infra Retirement Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-time, explicit retirement workflow for the legacy `personal-infra` workspace that uses a dedicated Terraform state boundary, inventories the retirement state, rejects unsafe destroy plans, and keeps `sandbox-infra` as the only active baseline workflow.

**Architecture:** Keep `infra/aws/dbx/databricks/us-west-1` create-only for steady-state work. Add a retirement-only local backend config plus small shell guardrails that operate on the same root state, then document a written preserve-versus-destroy contract and a runbook for both historical-state recovery and import-based reconstruction. Anything that cannot be proven both `personal-infra`-owned and safely representable in the current root stays out of Terraform destroy and is surfaced for manual adjudication rather than expanding the root back into an adopt-existing-workspace mode.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider, AWS provider, Bash, `jq`, `direnv`, Markdown

---

**Spec:** `docs/superpowers/specs/2026-03-20-personal-infra-retirement-design.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each shell guardrail change. Fixture-driven shell tests are the required “tests” for this workflow.
- Use `@verification-before-completion` before claiming the retirement workflow is ready.
- Use `@requesting-code-review` after the final verification pass.
- Work in a dedicated worktree. Do not implement this plan in a dirty shared tree.
- Before any live import, plan, apply, or destroy, confirm scope with the human: this workflow touches account-level resources, workspace-level resources, and Unity Catalog metastore-assignment behavior. Do not proceed on a looser scope assumption.
- Do not reintroduce `workspace_source`, `existing_workspace_host`, `existing_workspace_id`, or any other adopt-existing-workspace mode into the steady-state root.
- Do not un-comment dormant identity, catalog, service-principal, or warehouse roots merely to chase uncertain historical objects. If a live object cannot be proven both `personal-infra`-owned and representable in the current root, record it in the manual-adjudication section instead of automating its deletion.
- Use the repo-standard Terraform command shape for live runs:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 ...
```

- Generated `.tfstate`, `.tfplan`, and inventory output files must stay out of git.
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Create these retirement workflow files:

- `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.local.tfbackend`
- `infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh`
- `infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh`
- `infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-empty.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-populated.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-sandbox-contamination.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-delete-only.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-empty.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-mixed-actions.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-forbidden-metastore.json`
- `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-sandbox-contamination.json`
- `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md`
- `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md`

Modify these operator-guidance files:

- `infra/aws/dbx/databricks/us-west-1/README.md`
- `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`

Reference these existing files during implementation, but do not change them unless verification uncovers a real defect:

- `AGENTS.md`
- `ARCHITECTURE.md`
- `docs/superpowers/specs/2026-03-20-personal-infra-retirement-design.md`
- `infra/aws/dbx/databricks/us-west-1/backend.tf`
- `infra/aws/dbx/databricks/us-west-1/main.tf`
- `infra/aws/dbx/databricks/us-west-1/locals.tf`
- `infra/aws/dbx/databricks/us-west-1/credential.tf`
- `infra/aws/dbx/databricks/us-west-1/root_s3_bucket.tf`
- `infra/aws/dbx/databricks/us-west-1/network.tf`
- `infra/aws/dbx/databricks/us-west-1/privatelink.tf`
- `infra/aws/dbx/databricks/us-west-1/provider.tf`
- `infra/aws/dbx/databricks/us-west-1/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend`
- `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`

Responsibilities:

- `personal-infra-retirement.local.tfbackend`: hard-code the retirement state path so destroy work cannot silently reuse the sandbox backend or the unqualified default local state.
- `render_personal_infra_retirement_inventory.sh`: render a human-reviewable inventory from retirement state and fail fast when the state is empty or obviously points at sandbox resources.
- `verify_personal_infra_retirement_destroy_plan.sh`: reject empty or mixed-action destroy plans and reject plans that touch preserved shared objects or obvious sandbox markers.
- `scripts/testdata/*` plus `test_personal_infra_retirement_guardrails.sh`: provide offline regression coverage for the two shell guardrails without requiring live Databricks or AWS access.
- `personal-infra-retirement-contract.md`: define the written preserve-versus-destroy contract, including automated destroy scope versus manual-adjudication scope.
- `personal-infra-retirement.md`: document the end-to-end retirement runbook for both historical-state recovery and import-based reconstruction.
- `README.md`: keep sandbox-first guidance primary and link the retirement workflow without treating it as an everyday scenario.
- `scenario1.premium-existing.tfvars`: relabel this file as retirement-only historical input, not as an active deployment scenario.
- `template.tfvars.example`: remove `personal-infra` as the implied normal prefix and point operators toward sandbox-first create-only work.

## Chunk 1: Retirement State Boundary And Guardrails

### Task 1: Add The Dedicated Retirement Backend Config

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.local.tfbackend`
- Reference: `infra/aws/dbx/databricks/us-west-1/backend.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend`

- [ ] **Step 1: Add the dedicated retirement backend file**

Write `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.local.tfbackend` with exactly:

```hcl
path = "personal-infra-retirement.terraform.tfstate"
```

- [ ] **Step 2: Reinitialize Terraform against the retirement backend**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend
```

Expected: `terraform init` succeeds and reports the local backend reconfigured to `personal-infra-retirement.terraform.tfstate`.

- [ ] **Step 3: Prove the fresh retirement backend is empty before state recovery or import**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Expected: no output. If resources already appear here, stop because the retirement backend is pointing at the wrong state file.

- [ ] **Step 4: Commit the backend entrypoint after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.local.tfbackend
git commit -m "feat(retirement): add dedicated personal-infra backend"
```

Expected: one commit containing only the retirement backend config.

### Task 2: Add A Failing Inventory Guardrail Test, Then Implement The Inventory Script

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-empty.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-populated.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-sandbox-contamination.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh`

- [ ] **Step 1: Create the three state fixtures first**

Write `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-empty.json` with exactly:

```json
{
  "version": 4,
  "terraform_version": "1.10.0",
  "serial": 1,
  "lineage": "retirement-empty",
  "outputs": {},
  "resources": []
}
```

Write `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-populated.json` with a minimal personal-infra-like state snapshot, for example:

```json
{
  "version": 4,
  "terraform_version": "1.10.0",
  "serial": 2,
  "lineage": "retirement-populated",
  "outputs": {
    "workspace_id": {
      "value": "1234567890123456",
      "type": "string"
    }
  },
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "root_storage_bucket",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "attributes": {
            "id": "personal-infra-workspace-root-storage",
            "bucket": "personal-infra-workspace-root-storage"
          }
        }
      ]
    },
    {
      "module": "module.databricks_mws_workspace",
      "mode": "managed",
      "type": "databricks_mws_workspaces",
      "name": "workspace",
      "provider": "provider[\"registry.terraform.io/databricks/databricks\"].mws",
      "instances": [
        {
          "attributes": {
            "workspace_id": "1234567890123456",
            "workspace_name": "personal-infra"
          }
        }
      ]
    }
  ]
}
```

Write `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-sandbox-contamination.json` by copying the populated fixture and changing the bucket and workspace names to `sandbox-infra`.

- [ ] **Step 2: Write the inventory assertions before the inventory script exists**

Write `infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh` with an inventory-only test section first:

```bash
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
```

- [ ] **Step 3: Run the test runner and verify it fails before implementation**

Run:

```bash
bash infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
```

Expected: FAIL with `render_personal_infra_retirement_inventory.sh` missing or non-executable.

- [ ] **Step 4: Implement the inventory script with a testable `--state-json` mode**

Write `infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh` with this structure:

```bash
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
```

- [ ] **Step 5: Make the scripts executable and re-run the test runner**

Run:

```bash
chmod +x infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh
chmod +x infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
bash infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
```

Expected: PASS. The populated fixture succeeds and both the empty and sandbox-contaminated fixtures fail.

- [ ] **Step 6: Commit the inventory guardrail after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh
git add infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-empty.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-populated.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-state-sandbox-contamination.json
git commit -m "feat(retirement): add retirement state inventory guardrail"
```

Expected: one commit containing the inventory script, its tests, and its fixtures.

### Task 3: Add A Failing Destroy-Plan Guardrail Test, Then Implement The Plan Verifier

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-delete-only.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-empty.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-mixed-actions.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-forbidden-metastore.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-sandbox-contamination.json`
- Create: `infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh`

- [ ] **Step 1: Add the five plan fixtures**

Write `retirement-plan-delete-only.json` with a minimal all-delete plan, for example:

```json
{
  "format_version": "1.2",
  "resource_changes": [
    {
      "address": "aws_s3_bucket.root_storage_bucket",
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "root_storage_bucket",
      "change": {
        "actions": ["delete"],
        "before": {
          "bucket": "personal-infra-workspace-root-storage"
        },
        "after": null
      }
    },
    {
      "address": "module.databricks_mws_workspace.databricks_mws_workspaces.workspace",
      "mode": "managed",
      "type": "databricks_mws_workspaces",
      "name": "workspace",
      "change": {
        "actions": ["delete"],
        "before": {
          "workspace_name": "personal-infra",
          "workspace_id": "1234567890123456"
        },
        "after": null
      }
    }
  ]
}
```

Write `retirement-plan-empty.json` with `resource_changes: []`.

Write `retirement-plan-mixed-actions.json` by copying the delete-only fixture and changing one resource to:

```json
"actions": ["update"]
```

Write `retirement-plan-forbidden-metastore.json` with a delete action against:

```json
"address": "module.unity_catalog_metastore_creation.databricks_metastore.this[0]",
"type": "databricks_metastore"
```

Write `retirement-plan-sandbox-contamination.json` by copying the delete-only fixture and changing the bucket or workspace name to `sandbox-infra`.

- [ ] **Step 2: Extend the test runner with destroy-plan assertions before the verifier exists**

Append this block to `infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh`:

```bash
"$SCRIPTS_DIR/verify_personal_infra_retirement_destroy_plan.sh" \
  --plan-json "$TESTDATA_DIR/retirement-plan-delete-only.json" \
  >"$tmpdir/delete-only.out"

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
done
```

- [ ] **Step 3: Run the test runner and verify it fails before implementation**

Run:

```bash
bash infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
```

Expected: FAIL with `verify_personal_infra_retirement_destroy_plan.sh` missing or non-executable.

- [ ] **Step 4: Implement the destroy-plan verifier with a testable `--plan-json` mode**

Write `infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh` with this structure:

```bash
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
```

- [ ] **Step 5: Make the verifier executable and re-run the full guardrail suite**

Run:

```bash
chmod +x infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh
bash infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
```

Expected: PASS. The delete-only fixture succeeds and the empty, mixed-action, forbidden-metastore, and sandbox-contaminated fixtures all fail.

- [ ] **Step 6: Commit the destroy-plan guardrail after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh
git add infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-delete-only.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-empty.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-mixed-actions.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-forbidden-metastore.json
git add infra/aws/dbx/databricks/us-west-1/scripts/testdata/retirement-plan-sandbox-contamination.json
git commit -m "feat(retirement): add destroy-plan safety checks"
```

Expected: one commit containing only the verifier, the expanded test runner, and the plan fixtures.

## Chunk 2: Contract And Runbook

### Task 4: Write The Preserve-Versus-Destroy Contract

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md`
- Reference: `ARCHITECTURE.md`
- Reference: `docs/superpowers/specs/2026-03-20-personal-infra-retirement-design.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/main.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/credential.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/root_s3_bucket.tf`

- [ ] **Step 1: Write the top-level preserve set exactly as approved**

Start `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md` with these sections and bullets:

```md
# Personal Infra Retirement Contract

## Preserve

- Databricks account container and account-scoped configuration that serves multiple workspaces
- The shared Unity Catalog metastore itself
- Existing Okta SCIM-provisioned users and the SCIM-managed `okta-databricks-users` access path
```

- [ ] **Step 2: Define the automated Terraform destroy set using current-root addresses**

Add an `## Destroy Through Retirement State` section that lists the current-root-managed objects that are safe to represent in retirement state when they are provably `personal-infra`-owned:

- `aws_iam_role.cross_account_role`
- `aws_iam_role_policy.cross_account`
- `aws_s3_bucket.root_storage_bucket`
- `aws_s3_bucket_versioning.root_bucket_versioning`
- `aws_s3_bucket_server_side_encryption_configuration.root_storage_bucket_sse_s3[0]`
- `aws_s3_bucket_public_access_block.root_storage_bucket`
- `aws_s3_bucket_policy.root_bucket_policy`
- `module.databricks_mws_workspace.databricks_mws_credentials.this`
- `module.databricks_mws_workspace.databricks_mws_storage_configurations.this`
- `module.databricks_mws_workspace.databricks_mws_workspaces.workspace`
- `module.unity_catalog_metastore_assignment.databricks_metastore_assignment.default_metastore`
- `module.user_assignment.databricks_mws_permission_assignment.workspace_access`

State explicitly that additional resources may be included only when they are both present in the retirement state and clearly attributable to `personal-infra`.

- [ ] **Step 3: Define the manual-adjudication boundary**

Add an `## Manual Adjudication Required` section with these rules:

- any live object not represented in the retirement state inventory
- any Unity Catalog object on the shared metastore whose ownership cannot be proven from current config, historical state, or `personal-infra` naming
- any object with `sandbox` naming or any known non-`personal-infra` consumer
- any resource whose only safe deletion path would require reintroducing adopt-existing or multi-environment abstractions into the root

- [ ] **Step 4: Add explicit plan rejection rules**

Add an `## Reject The Destroy Plan If` section that states the human must reject any plan that:

- deletes `databricks_metastore` or `module.unity_catalog_metastore_creation.*`
- references `okta-databricks-users`, `databricks_user`, or any other SCIM-user deletion path
- includes create, update, or replace actions
- includes `sandbox` resource names, addresses, or IDs
- contains resources whose ownership is still uncertain

- [ ] **Step 5: Verify the contract headings and critical terms are present**

Run:

```bash
rg -n "^## Preserve$|^## Destroy Through Retirement State$|^## Manual Adjudication Required$|^## Reject The Destroy Plan If$|okta-databricks-users|module\\.unity_catalog_metastore_creation" infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md
```

Expected: one hit per required heading plus the explicit shared-object rejection terms.

- [ ] **Step 6: Commit the contract after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md
git commit -m "docs(retirement): define personal-infra destroy contract"
```

Expected: one commit containing only the preserve-versus-destroy contract.

### Task 5: Write The Retirement Runbook For Both Entry Paths

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.local.tfbackend`
- Reference: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh`
- Reference: `infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh`
- Reference: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- Reference: `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend`
- Reference: `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`

- [ ] **Step 1: Write the runbook prerequisites and retirement-only warnings**

Start `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md` with:

- a one-paragraph statement that `sandbox-infra` is the active baseline and this runbook is one-time retirement guidance only
- a short “Do not start here” list that forbids:
  - `terraform destroy` from the default local state
  - `terraform destroy` from the sandbox backend
  - destroy apply without both the inventory script and the destroy-plan verifier
- a “Files used in this workflow” list naming:
  - `scenario1.premium-existing.tfvars`
  - `personal-infra-retirement.local.tfbackend`
  - `personal-infra-retirement-contract.md`
  - both shell guardrail scripts

- [ ] **Step 2: Document the historical-state recovery path with exact commands**

Add a `## Path A: Recover Historical Retirement State` section with these commands:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state push /absolute/path/to/personal-infra-historical.tfstate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh > /tmp/personal-infra-retirement-inventory.md
```

Expected: `state list` shows a non-empty retirement state and the inventory script emits a reviewable list of managed resources.

After the inventory is rendered, state explicitly that the operator must prune any preserved or uncertain entries out of the retirement state before planning destroy, for example:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state rm 'module.unity_catalog_metastore_creation.databricks_metastore.this[0]'
```

The runbook must explain that `terraform state rm` removes the object from retirement management without deleting the remote object.

- [ ] **Step 3: Document the import-based reconstruction path with the exact address checklist**

Add a `## Path B: Reconstruct Retirement State By Import` section that:

- starts from the same `init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend` command
- requires `terraform state list` to be empty before the first import
- lists the current-root addresses in import order:
  - `aws_iam_role.cross_account_role`
  - `aws_iam_role_policy.cross_account`
  - `aws_s3_bucket.root_storage_bucket`
  - `aws_s3_bucket_versioning.root_bucket_versioning`
  - `aws_s3_bucket_server_side_encryption_configuration.root_storage_bucket_sse_s3[0]`
  - `aws_s3_bucket_public_access_block.root_storage_bucket`
  - `aws_s3_bucket_policy.root_bucket_policy`
  - `module.databricks_mws_workspace.databricks_mws_credentials.this`
  - `module.databricks_mws_workspace.databricks_mws_storage_configurations.this`
  - `module.databricks_mws_workspace.databricks_mws_workspaces.workspace`
- `module.unity_catalog_metastore_assignment.databricks_metastore_assignment.default_metastore`
- `module.user_assignment.databricks_mws_permission_assignment.workspace_access`
- states explicitly: only document import commands whose resource-specific import IDs have been verified in the provider docs; do not guess Databricks import ID formats
- states explicitly: anything not on the checklist, or anything whose ownership is still uncertain, stays out of Terraform state and moves to manual adjudication
- ends with the same inventory command from Path A

- [ ] **Step 4: Document destroy-plan generation, verification, human review, and apply**

Add a `## Generate, Verify, Review, And Apply The Destroy Plan` section with these commands:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -destroy -var-file=scenario1.premium-existing.tfvars -out=personal-infra-retirement.destroy.tfplan
infra/aws/dbx/databricks/us-west-1/scripts/verify_personal_infra_retirement_destroy_plan.sh infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.destroy.tfplan
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color personal-infra-retirement.destroy.tfplan
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply personal-infra-retirement.destroy.tfplan
```

State clearly that the human must compare both the inventory and the destroy-plan summary against `personal-infra-retirement-contract.md` before apply.

- [ ] **Step 5: Document post-destroy verification exactly as required by the spec**

Add a `## Post-Destroy Verification` section with:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected:

- the retirement backend `state list` is empty after destroy
- the sandbox plan succeeds and does not propose destructive drift
- the operator manually confirms the old `personal-infra` workspace no longer exists in the Databricks account UI or API

- [ ] **Step 6: Verify the runbook covers both entry paths and all guardrails**

Run:

```bash
rg -n "^## Path A: Recover Historical Retirement State$|^## Path B: Reconstruct Retirement State By Import$|plan -destroy -var-file=scenario1\\.premium-existing\\.tfvars|verify_personal_infra_retirement_destroy_plan|sandbox\\.local\\.tfbackend|scenario2\\.sandbox-create-managed\\.tfvars" infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md
```

Expected: hits for both entry paths, destroy-plan generation, the verifier script, and the sandbox post-destroy check.

- [ ] **Step 7: Commit the runbook after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md
git commit -m "docs(retirement): add personal-infra retirement runbook"
```

Expected: one commit containing only the retirement runbook.

## Chunk 3: Active Guidance Cleanup And Verification

### Task 6: Make Sandbox The Only Active Workflow In Checked-In Guidance

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`
- Reference: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/personal-infra-retirement-contract.md`

- [ ] **Step 1: Relabel scenario 1 as retirement-only historical input**

Replace the opening comments in `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars` with:

```hcl
# Retirement-only historical input for the legacy personal-infra workspace.
# Do not use this file for new workspace creation.
# Active steady-state work uses scenario2.sandbox-create-managed.tfvars.
```

Leave the existing `personal-infra` values intact.

- [ ] **Step 2: Stop using `personal-infra` as the implied default in the generic template**

Update the top of `infra/aws/dbx/databricks/us-west-1/template.tfvars.example` so it says:

```hcl
# Generic tfvars reference only.
# Active steady-state work uses scenario2.sandbox-create-managed.tfvars.
# Legacy personal-infra teardown uses personal-infra-retirement.md.
```

Change:

```hcl
resource_prefix = "personal-infra"
```

to:

```hcl
resource_prefix = "example-workspace"
```

- [ ] **Step 3: Add a short retirement pointer to the README without displacing sandbox-first guidance**

Update `infra/aws/dbx/databricks/us-west-1/README.md` so that:

- `## Sandbox Workspace Workflow` remains the first active workflow section
- a new short `## Personal Infra Retirement` section links readers to:
  - `personal-infra-retirement.md`
  - `personal-infra-retirement-contract.md`
- the `## Create-Only Identity Rollout` section no longer frames `scenario1.premium-existing.tfvars` as a normal rollout path and instead calls it retirement-only historical input

- [ ] **Step 4: Verify the checked-in operator guidance no longer treats scenario 1 as active**

Run:

```bash
rg -n "scenario1\\.premium-existing\\.tfvars|personal-infra" infra/aws/dbx/databricks/us-west-1/README.md infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars infra/aws/dbx/databricks/us-west-1/template.tfvars.example
```

Expected: any remaining `scenario1` or `personal-infra` references are clearly retirement-only or historical-context references, not active deployment guidance.

- [ ] **Step 5: Commit the guidance cleanup after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git add infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars
git add infra/aws/dbx/databricks/us-west-1/template.tfvars.example
git commit -m "docs(retirement): make sandbox the active baseline"
```

Expected: one commit containing only README and tfvars guidance changes.

### Task 7: Run Offline Guardrails And Dry-Run Backend Verification

**Files:**
- Verify only

- [ ] **Step 1: Re-run the offline guardrail suite**

Run:

```bash
bash infra/aws/dbx/databricks/us-west-1/scripts/test_personal_infra_retirement_guardrails.sh
```

Expected: PASS.

- [ ] **Step 2: Reinitialize the retirement backend and confirm the inventory script refuses an empty live state**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=personal-infra-retirement.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
infra/aws/dbx/databricks/us-west-1/scripts/render_personal_infra_retirement_inventory.sh
```

Expected:

- `state list` prints no resources on a fresh backend
- the inventory script exits non-zero with the “retirement state is empty” guardrail message

- [ ] **Step 3: Reinitialize the sandbox backend and confirm the steady-state sandbox plan still works**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected: the plan command succeeds. If credentials or remote access are unavailable, record the exact gap rather than claiming the retirement workflow is fully verified.

- [ ] **Step 4: Review the diff for scope control**

Run:

```bash
git diff --stat
git diff -- infra/aws/dbx/databricks/us-west-1 docs/superpowers/plans/2026-03-20-personal-infra-retirement.md
```

Expected: the change is limited to the retirement backend file, the shell guardrails with their fixtures, the retirement docs, and the guidance cleanup.

- [ ] **Step 5: Request code review after the verification pass**

Use `@requesting-code-review` and include the spec path, the new retirement runbook path, and the guardrail test command in the review request.
