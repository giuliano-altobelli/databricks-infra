# Governed Tags Module

## Summary

- **Module name**: `unity_catalog_governed_tags`
- **One-liner**: Manage user-defined, account-wide Databricks governed tags through a workspace-level provider.

## Scope

- In scope:
  - user-defined governed tags
  - governed tags without allowed values
  - governed tags with allowed values
  - required descriptions
  - exact, case-sensitive key and value preservation
- Out of scope:
  - system governed tags
  - governed-tag permissions
  - tag assignments
  - account and allowed-value collection limits
  - root-module configuration

## Interfaces

- Required inputs:
  - `tags`: governed tags keyed by their exact tag key, each with a required description
- Optional inputs:
  - `enabled`: whether the module creates and validates governed tags
  - `tags[*].values`: allowed values; omission or an empty set creates a key-only governed tag
- Outputs:
  - `tags`: managed governed tags keyed identically to the input

## Provider Context

- Provider: `databricks/databricks`
- Authentication mode: workspace-level provider
- Scope: account-wide governed-tag policy

## Constraints

- Keys and values are non-empty and at most 256 characters.
- Keys and values use UTF-8 and preserve case.
- Keys and values cannot contain `* . / < > % & ? \ =` or ASCII control characters 0 through 31.
- Keys and values cannot begin or end with whitespace.
- Descriptions are required and cannot be empty or whitespace-only.
- The module does not normalize keys, values, or descriptions.

## Validation

- `terraform fmt -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `terraform test`
