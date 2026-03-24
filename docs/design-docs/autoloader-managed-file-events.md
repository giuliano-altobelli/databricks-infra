# Auto Loader With Managed File Events

Date: 2026-03-24

## Objective

Show the recommended Unity Catalog pattern for ingesting new Parquet files from S3 with Auto Loader using `cloudFiles.useManagedFileEvents`.

This guide is intentionally standalone. It explains the AWS policy shape, the Databricks stream configuration, and what each option does.

## When To Use This Pattern

Use this pattern when:

- Your source data lives in an S3 prefix governed by a Unity Catalog external location.
- You want Auto Loader to discover new files with managed file events instead of the older classic notification flow.
- You want the stream to keep ingesting as new files arrive while the job stays running.

Do not use this pattern if you want a one-off batch copy. Do not use it if you are already committed to classic `cloudFiles.useNotifications` queues.

## Prerequisites

- The source path must be in a Unity Catalog external location.
- File events must be enabled on that external location. New external locations have file events enabled by default; existing locations may need to be edited first.
- The stream must run on compute that supports managed file events. In Databricks this means dedicated access mode and DBR 14.3 LTS or above.
- Keep checkpoint and schema tracking in a separate storage location that the stream can write to.

## AWS Policy Requirements

`cloudFiles.useManagedFileEvents` is not just a stream option. Databricks also needs AWS permissions on the IAM role behind the storage credential to set up and manage the notification plumbing for the source bucket.

### Recommended automatic setup

If Databricks should create and manage the event plumbing, the storage credential role needs permission to:

- Read and update the S3 bucket notification configuration
- Create and manage the Databricks-managed SNS and SQS resources used for file events

Typical actions are:

| AWS action group | Purpose | Resource scope |
| --- | --- | --- |
| `s3:GetBucketNotification`, `s3:PutBucketNotification` | Read and update the bucket notification config | The source bucket ARN |
| `sns:CreateTopic`, `sns:Publish`, `sns:Subscribe`, `sns:GetTopicAttributes`, `sns:SetTopicAttributes`, `sns:TagResource` | Manage the SNS side of the file-event pipeline | Databricks-managed `csms-*` SNS ARNs |
| `sqs:CreateQueue`, `sqs:DeleteMessage`, `sqs:ReceiveMessage`, `sqs:SendMessage`, `sqs:GetQueueUrl`, `sqs:GetQueueAttributes`, `sqs:SetQueueAttributes`, `sqs:TagQueue`, `sqs:ChangeMessageVisibility`, `sqs:PurgeQueue` | Manage and consume the SQS side of the file-event pipeline | Databricks-managed `csms-*` SQS ARNs |

Databricks documentation also keeps the normal source-data permissions separate from the file-event plumbing. If the same IAM role is used to read the source objects directly, keep the usual S3 read permissions on the source bucket/prefix as well.

The full automatic-file-events policy in the Databricks docs also includes list and teardown statements for the managed `csms-*` resources. In practice that means the role can also need:

- `sqs:ListQueues`, `sqs:ListQueueTags`
- `sns:ListTopics`
- `sns:ListSubscriptionsByTopic`
- `sns:DeleteTopic`
- `sqs:DeleteQueue`

### If you provide the queue yourself

If you do not want Databricks to create the notification plumbing, you can supply the queue externally.

In that case:

- Create the SQS queue yourself.
- Subscribe the queue to the bucket's S3 event notifications for the source prefix.
- Give the IAM role only the SQS consume permissions it needs for that queue.

This is more manual, but it reduces the amount of AWS infrastructure Databricks has to manage.

## Example Layout

Use three paths:

- Source files: `s3://company-sandbox-bronze-raw/incoming/orders/`
- Schema metadata: `s3://company-sandbox-bronze-raw/_autoloader/orders/schema`
- Checkpoint metadata: `s3://company-sandbox-bronze-raw/_autoloader/orders/checkpoint`

The schema and checkpoint paths can share the same root if you want, but separate subdirectories make the intent clearer.

## Complete Parquet Example

```python
schema_path = "s3://company-sandbox-bronze-raw/_autoloader/orders/schema"
checkpoint_path = "s3://company-sandbox-bronze-raw/_autoloader/orders/checkpoint"
source_path = "s3://company-sandbox-bronze-raw/incoming/orders/"

(spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "parquet")
  .option("cloudFiles.schemaLocation", schema_path)
  .option("cloudFiles.useManagedFileEvents", "true")
  .option("cloudFiles.includeExistingFiles", "false")
  .load(source_path)
  .writeStream
  .option("checkpointLocation", checkpoint_path)
  .toTable("bronze.orders"))
```

## What Each Setting Does

| Setting | What it does | Notes |
| --- | --- | --- |
| `spark.readStream.format("cloudFiles")` | Turns on Auto Loader | Required for incremental cloud-file ingestion |
| `cloudFiles.format = "parquet"` | Tells Auto Loader the file format | Use `parquet` for Parquet sources |
| `cloudFiles.schemaLocation` | Stores schema inference and evolution metadata | Put this in a path that the stream can write to |
| `cloudFiles.useManagedFileEvents = "true"` | Uses Databricks-managed file events instead of classic notification mode | Requires a file-events-enabled Unity Catalog external location |
| `cloudFiles.includeExistingFiles = "false"` | Ignores files that already existed when the stream first started | Set this to `true` if you want an initial backfill of existing files |
| `load(source_path)` | Points Auto Loader at the source S3 prefix | This is the prefix that gets monitored for new files |
| `writeStream.option("checkpointLocation", ...)` | Stores streaming checkpoint state | This tracks progress and restart state |
| `.toTable("bronze.orders")` | Writes the stream to a Delta table | Replace with your target table name |

## Operational Notes

- Auto Loader does not need a separate AWS Lambda-style trigger. The stream keeps running, and managed file events help it discover new files quickly.
- If you want the whole Databricks job to start only when files land, use a Databricks file-arrival job trigger instead. That is a separate feature from Auto Loader.
- Do not set `cloudFiles.useNotifications` in the same stream. That is the older classic notification path.
- If your source location already exists, make sure file events are enabled there before turning on `cloudFiles.useManagedFileEvents`.

## Quick Rule Of Thumb

- Use `useManagedFileEvents` for Unity Catalog external locations and new workloads.
- Use `useNotifications` only if you are intentionally operating the older classic queue-based flow.
- Keep schema and checkpoint paths outside the source prefix and give them a dedicated writable location.
