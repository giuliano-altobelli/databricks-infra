# Databricks infra

We are going to have an open ended discussion regarding databricks infra design for a large scale enterprise with large teams, products, business domains, and data sources. The goal is to control permissions as granular as possible.

## Assumptions
- 3 workspaces (dev,qa,prod)
- N catalogs based on business domain and data sources (e.g. finops, peopleops, netsuite, jira, etc...)
- 4 data layers (raw, base, staging, final)
- dev workspace must be locked down to the individual developer meaning we could have a schema per developer where that developer can only use and view that schema

## Design
- Straming pipelines will 100% be native to databricks only
- Batch jobs will be using autoloader to read data from s3 object storage and using sqlmesh for data transformations
- Use ABAC driven by an entitlement table to prevent exploding groups/schemas

## Context
- For sqlmesh documentation use context7 libraryId `/tobikodata/sqlmesh`

## Questions
- If a dev makes a change to a sqlmesh model in the dev workspace, how can the upstream tables reflect production to make sure the dev is making up to date changes that will reflect prod?