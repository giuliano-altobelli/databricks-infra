# Platform Admins Group Design

Date: 2026-02-27

## Objective

Validate the `databricks_account/users_groups` module end-to-end by creating a `platform_admins` group with `giulianoaltobelli@gmail.com` as the only member, and ensuring the configuration covers all three scopes:

- Account-level
- Workspace-level
- Unity Catalog

## Scope

In scope:

- Configure `platform_admins` in `identify.tf`
- Use `roles = ["account_admin"]` for account-wide admin validation
- Add user membership for `giulianoaltobelli@gmail.com`
- Apply workspace permissions/entitlements through `module.users_groups`
- Apply Unity Catalog catalog grant for `platform_admins`
- Extend module input to support optional `users[*].force`

Out of scope:

- Removing bootstrap `module.user_assignment`
- Removing existing direct UC admin grant in `uc_existing_catalog.tf`
- Refactoring to multi-workspace identity fan-out

## Confirmed Context

- Root module currently wires `module.users_groups` with two provider aliases:
  - `databricks.mws` (account scope)
  - `databricks.created_workspace` (workspace scope)
- `identify.tf` already contains placeholders for `platform_admins` and identity users.
- `module.user_assignment` already assigns workspace `ADMIN` to `var.admin_user`.
- `unity_catalog_group_catalog_privileges` currently includes `platform_admins = ["ALL_PRIVILEGES"]`.

## Approaches Considered

1. Minimal validation path (selected)
- Keep bootstrap admin resources unchanged.
- Enable `platform_admins` + membership + `account_admin` role in `identify.tf`.
- Add optional `force` on module users to handle pre-existing users if needed.

2. Full migration to group-centric admin
- Replace direct bootstrap user assignment and direct UC grant with group-only ownership.
- Rejected for this validation pass due to larger behavior change.

3. Group-only smoke test without membership
- Create group and grants only.
- Rejected because it does not validate user-membership management in module flow.

## Selected Design

### Architecture

- `identify.tf` drives identity intent via:
  - `local.identity_groups`
  - `local.identity_users`
  - `local.unity_catalog_group_catalog_privileges`
- `module.users_groups` remains the central identity provisioning component.
- UC grants continue to be applied by `databricks_grant.unity_catalog_group_catalog_grants` referencing group display names.

### Component Changes

- `infra/aws/dbx/databricks/us-west-1/identify.tf`
  - Add concrete `platform_admins` group definition.
  - Add one concrete user (`giulianoaltobelli@gmail.com`) in `identity_users`, mapped to `platform_admins`.
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf`
  - Add optional `force` to `users` object schema.
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf`
  - Pass `force` into both user resources (`users` and `users_protected`).
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md`
  - Document plain-group vs `account_admin` group distinction and examples.

### Data Flow

1. Root locals (`identity_groups`, `identity_users`) feed module inputs.
2. Module creates/updates account-scoped users/groups/memberships/roles and workspace assignments via `databricks.mws`.
3. Module applies workspace entitlements via `databricks.workspace`.
4. Root-level `databricks_grant` applies UC catalog privileges to the group display name.

### Error Handling and Safety

- Preserve current validations:
  - Missing group references in user memberships fail plan.
  - Invalid workspace permissions fail validation.
  - Invalid entitlement combinations fail validation.
- Keep bootstrap admin assignment unchanged to limit blast radius during validation.
- `force` is optional and only used when explicitly set per user.

## Test and Verification Plan

Run (outside sandbox):

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Pre-checks:

- `terraform fmt -recursive`
- `terraform validate`

Expected plan outcomes:

- `platform_admins` group creation (or adoption/update behavior if existing)
- `account_admin` group role attachment
- Membership of `giulianoaltobelli@gmail.com` in `platform_admins`
- Workspace permission assignment/entitlements as configured
- UC catalog grant for `platform_admins`

## Acceptance Criteria

- `platform_admins` exists and is module-managed.
- `giulianoaltobelli@gmail.com` is the only configured member in Terraform input.
- Group has `account_admin` role.
- Workspace-level access is present for the target workspace.
- UC catalog grant is present for group principal.
- Plan/apply complete without validation errors.

## Notes

- Duplicate workspace admin assignment may appear functionally redundant because bootstrap assignment remains; this is acceptable for this validation pass.
- Post-validation cleanup can consolidate admin ownership to group-centric resources in a separate change.
