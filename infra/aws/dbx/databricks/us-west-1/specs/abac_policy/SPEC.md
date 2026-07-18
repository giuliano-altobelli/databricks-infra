# ABAC Policy Feature Spec

## Summary

- Provide a lightweight Databricks ABAC row-filter policy path that can target catalog or schema scope.
- Bootstrap an isolated demonstration catalog and `protected` schema in both development and production before policy resources are introduced.

## Environment Catalog Contract

- The stable Terraform catalog key is `abac_demo` in every workspace.
- The catalog name is supplied by the workspace variable `abac_demo_catalog_name`; it must not be hardcoded in `catalogs_config.tf`.
- Sandbox/development uses `dev_abac_demo`.
- Production uses `prod_abac_demo`.
- Both workspace var files enable the demo catalog.
- The only demo schema is `protected`.
- The catalog display name defaults to `abac_demo_catalog_name` and can be overridden with `abac_demo_catalog_display_name`.

## Policy Contract (Next Phase)

- Support catalog and schema policy scopes.
- Row filters are in scope; column masks are out of scope.
- Fail during Terraform planning when any required governed tag key/value or UDF is missing.
- The boundary matcher is `abac_boundary = abac-general-okta-group`.
- The protected-column matcher is `protected_column = okta_group_names`.
- Development resolves the policy UDF from `dev_security.policies`; production resolves it from `prod_security.policies`.
- Policy recipients are `TO okta-databricks-users EXCEPT Platform Admins`.

## Current Task Boundaries

- Replace the incorrectly named sandbox `prod_abac_demo` catalog with `dev_abac_demo`.
- Create `prod_abac_demo` in the production workspace.
- Do not provision a demo table or an ABAC policy in this task.

## Validation

- Terraform must detect when the enabled `abac_demo` caller is not wired to `var.abac_demo_catalog_name`.
- Sandbox plan must resolve the catalog and schema as `dev_abac_demo.protected`.
- Production plan must resolve the catalog and schema as `prod_abac_demo.protected`.
- Apply only reviewed, workspace-specific plans; do not apply unrelated authoritative-grant drift.
