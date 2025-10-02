# AWS DMS Terraform Module

This Terraform module provisions a secure, OPA-compliant AWS Database Migration Service (DMS) environment. It manages replication instances, endpoints, tasks, networking, IAM roles, CloudWatch logs, and S3 buckets needed for migrations.

---

## Mandatory AWS DMS Roles

AWS Database Migration Service depends on certain IAM roles. Some are **mandatory defaults** that AWS expects in every account, while others are required only when you use specific features like Secrets Manager.

- **`dms-vpc-role`** – **AWS required default**.  
  Allows DMS to create and manage network interfaces in your VPC.  
  Without this role, replication instances cannot launch.

- **`dms-cloudwatch-logs-role`** – **AWS required default**.  
  Allows DMS to write replication and task logs to CloudWatch Logs.  
  Without this role, task logging will fail.

- **`dms-secrets-mgr-role`** – **custom role required for Secrets Manager endpoints**.  
  This is **not provisioned by AWS by default**.  
  If you store database credentials in AWS Secrets Manager (recommended), DMS needs a role with `secretsmanager:GetSecretValue` it can assume.  
  By convention, most teams name it `dms-secrets-mgr-role`, but you may use a custom name if you pass the ARN when creating endpoints.

Important:  
- `dms-vpc-role` and `dms-cloudwatch-logs-role` must exist in the account before any DMS instance or task will succeed.  
- If you use Secrets Manager integration, you must also provision a `dms-secrets-mgr-role` (or equivalent) and pass its ARN to the module.

---

## Inputs

| Name | Type | Description | Default | Required |
|------|------|-------------|---------|----------|
| `prefix_name` | `string` | Lowercase, hyphenized prefix used for naming all DMS resources. | — | **Yes** |
| `subnet_ids` | `list(string)` | Subnet IDs for the DMS replication subnet group. | — | **Yes** |
| `vpc_security_group_ids` | `list(string)` | Security group IDs attached to the replication instance. | `[]` | No |
| `kms_key_arn` | `string` | Customer-managed KMS key ARN used for log group encryption and S3 buckets. | — | **Yes** |
| `dms_secrets_mgr_role_arn` | `string` | ARN of the custom DMS Secrets Manager role (must be created outside this module). | — | **Yes** |
| `dms_vpc_role_arn` | `string` | ARN of the AWS DMS VPC role. Must exist in the account. | `null` | No |
| `dms_cloudwatch_logs_role_arn` | `string` | ARN of the AWS DMS CloudWatch Logs role. Must exist in the account. | `null` | No |
| `endpoints` | `map(object)` | Map of DMS endpoints. Each must define: `endpoint_type`, `engine_name`, `secrets_manager_arn`. Optional `database_name` if using basic auth (when not embedding in secret JSON). | `{}` | **Yes** |
| `replication_tasks` | `map(object)` | Map of replication tasks. Must define: `source_endpoint`, `target_endpoint`, `migration_type`, `table_mappings` JSON. Optional `replication_settings` JSON. | `{}` | **Yes** |
| `tags` | `map(string)` | Resource tags. Must include `Environment`, `AIT`, `Repo`, `Owner`. | — | **Yes** |
| `instance_class` | `string` | Replication instance class. | `"dms.t3.medium"` | No |
| `allocated_storage` | `number` | Replication instance storage (GB). | `100` | No |
| `multi_az` | `bool` | Whether to deploy the replication instance in multiple AZs. | `false` | No |
| `log_retention_days` | `number` | CloudWatch Logs retention period (days). | `30` | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `kms_key_arn` | The ARN of the KMS key used for DMS resources (logs, buckets, instance). |
| `s3_assessment_bucket` | Name of the assessment S3 bucket. |
| `s3_assessment_bucket_arn` | ARN of the assessment S3 bucket. |
| `s3_assessment_logs_bucket` | Name of the assessment logs bucket. |
| `s3_assessment_logs_bucket_arn` | ARN of the assessment logs bucket. |
| `cloudwatch_log_group` | Name of the CloudWatch log group for DMS. |
| `replication_instance_id` | ID of the replication instance. |
| `replication_instance_arn` | ARN of the replication instance. |
| `dms_secrets_mgr_role_arn` | ARN of the DMS Secrets Manager role provided. |
| `dms_vpc_role_arn` | ARN of the AWS DMS VPC role provided. |
| `dms_cloudwatch_logs_role_arn` | ARN of the AWS DMS CloudWatch Logs role provided. |
| `endpoint_arns` | Map of DMS endpoint ARNs by key. |
| `replication_tasks` | Map of replication task IDs and ARNs. |
| `secrets_policies` | Map of attached Secrets Manager secret policies by key (if created outside, include IDs in outputs). |

---

## Usage

### Basic Example

```hcl
# DATA SOURCES
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"
}
data "aws_iam_role" "dms_cloudwatch_logs_role" {
  name = "dms-cloudwatch-logs-role"
}
data "aws_iam_role" "dms_secrets_mgr_role" {
  name = "dms-secrets-mgr-role"
}

# LOCALS
locals {
  source_pg = "sourcepg"
  target_pg = "targetpg"
}

# SECURITY GROUP FOR DMS INSTANCE
resource "aws_security_group" "dms" {
  name        = "${var.prefix_name}-dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # adjust for your environment
  }

  tags = merge(var.tags, {
    Name = "${var.prefix_name}-dms-sg"
  })
}

# SECRETS (inline example)
resource "aws_secretsmanager_secret" "source_pg" {
  name       = "${var.prefix_name}-srcpg"
  kms_key_id = aws_kms_key.dms.arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "source_pg" {
  secret_id = aws_secretsmanager_secret.source_pg.id
  secret_string = jsonencode({
    username = "dms_user",
    password = "CHANGEME",
    engine   = "postgres",
    host     = "source-db.example.com",
    port     = 5432,
    dbname   = "sourcedb",
    sslmode  = "require"
  })
}

resource "aws_secretsmanager_secret" "target_pg" {
  name       = "${var.prefix_name}-tgtpg"
  kms_key_id = aws_kms_key.dms.arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "target_pg" {
  secret_id = aws_secretsmanager_secret.target_pg.id
  secret_string = jsonencode({
    username = "dms_user",
    password = "CHANGEME",
    engine   = "postgres",
    host     = "target-db.example.com",
    port     = 5432,
    dbname   = "targetdb",
    sslmode  = "require"
  })
}

# MODULE USAGE
module "dms" {
  source                 = "../modules/dms"
  prefix_name            = var.prefix_name
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.dms.id]
  kms_key_arn            = aws_kms_key.dms.arn

  dms_secrets_mgr_role_arn     = data.aws_iam_role.dms_secrets_mgr_role.arn
  dms_vpc_role_arn             = try(data.aws_iam_role.dms_vpc_role.arn, null)
  dms_cloudwatch_logs_role_arn = try(data.aws_iam_role.dms_cloudwatch_logs_role.arn, null)

  endpoints = {
    "${local.source_pg}" = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      ssl_mode            = "require"
    }
    "${local.target_pg}" = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
      ssl_mode            = "require"
    }
  }

  replication_tasks = {
    full-load-task = {
      source_endpoint = local.source_pg
      target_endpoint = local.target_pg
      migration_type  = "full-load"

      table_mappings = jsonencode({
        rules = [{
          "rule-type" = "selection",
          "rule-id"   = "1",
          "rule-name" = "includeAll",
          "object-locator" = {
            "schema-name" = "%",
            "table-name"  = "%"
          },
          "rule-action" = "include"
        }]
      })

      replication_settings = jsonencode({
        Logging = {
          EnableLogging = true
        },
        FullLoadSettings = {
          TargetTablePrepMode = "DROP_AND_CREATE"
        }
      })
    }
  }

  tags = var.tags
}
```

---

### Robust Example

```hcl
locals {
  source_pg = "sourcepg"
  target_pg = "targetpg"
}

module "dms" {
  source                 = "../modules/dms"
  prefix_name            = "demo-dms"
  subnet_ids             = ["subnet-12345678", "subnet-abcdef12"]
  vpc_security_group_ids = [aws_security_group.dms.id]
  kms_key_arn            = aws_kms_key.dms.arn

  dms_secrets_mgr_role_arn     = data.aws_iam_role.dms_secrets_mgr_role.arn
  dms_vpc_role_arn             = data.aws_iam_role.dms_vpc_role.arn
  dms_cloudwatch_logs_role_arn = data.aws_iam_role.dms_cloudwatch_logs_role.arn

  endpoints = {
    "${local.source_pg}" = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      ssl_mode            = "require"
    }
    "${local.target_pg}" = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
      ssl_mode            = "require"
    }
  }

  replication_tasks = {
    full-load-task = {
      source_endpoint      = local.source_pg
      target_endpoint      = local.target_pg
      migration_type       = "full-load"
      table_mappings       = file("${path.module}/table-mappings/full-load.json")
      replication_settings = file("${path.module}/task-settings/full-load.json")
    }

    cdc-task = {
      source_endpoint      = local.source_pg
      target_endpoint      = local.target_pg
      migration_type       = "cdc"
      table_mappings       = file("${path.module}/table-mappings/cdc.json")
      replication_settings = file("${path.module}/task-settings/cdc.json")
    }
  }

  tags = var.tags
}
```

---

## JSON File Examples

### `table-mappings/full-load.json`
```json
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "includeAll",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
```

### `task-settings/full-load.json`
```json
{
  "Logging": {
    "EnableLogging": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE",
    "StopTaskCachedChangesApplied": false,
    "StopTaskCachedChangesNotApplied": false,
    "MaxFullLoadSubTasks": 8,
    "TransactionConsistencyTimeout": 600,
    "CommitRate": 10000
  },
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true
  }
}
```

### `table-mappings/cdc.json`
```json
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "2",
      "rule-name": "cdcAll",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
```

### `task-settings/cdc.json`
```json
{
  "Logging": {
    "EnableLogging": true
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true,
    "HandleSourceTableTruncated": true,
    "HandleSourceTableAltered": true
  }
}
```

---

## Gotchas

This module enforces AWS and OPA compliance rules. Keep these points in mind:

- **Naming Constraints**  
  - `prefix_name` must be lowercase, hyphenized, ≤ 50 characters, and cannot contain consecutive hyphens.  
  - Endpoint keys must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and must not end with a hyphen.  
  - Replication task keys must follow the same rules and must not exceed 255 characters including prefix and suffix.  

- **KMS Key Usage**  
  - You must supply a customer-managed KMS key ARN (`kms_key_arn`).  
  - This key encrypts CloudWatch Logs, S3 buckets, and DMS endpoints.  
  - The key policy must allow access to:  
    - Your AWS account root  
    - CloudWatch Logs (`logs.${region}.amazonaws.com`)  
    - The DMS Secrets Manager role you pass (`dms_secrets_mgr_role_arn`)  
  - Do not duplicate KMS permissions in secret resource policies; they belong in the KMS key policy.  

- **Secrets Manager Policies**  
  - All secrets for endpoints must have a resource policy (`aws_secretsmanager_secret_policy`).  
  - `block_public_policy = true` is enforced.  
  - Policies only allow `secretsmanager:GetSecretValue` to the DMS Secrets Manager role created in usage.  

- **Replication Tasks**  
  - Every replication task must reference valid `endpoints` keys.  
  - `table_mappings` and `replication_settings` must be valid JSON; this is validated at plan time.  
  - Inline JSON (`jsonencode`) is fine for small examples; use external JSON files (`file("...")`) for production.  
  - Tasks should include CloudWatch Logs settings if log visibility is required.  

- **Required AWS Roles**  
  - `dms-vpc-role` (AWS-required) must exist in the account for replication instances to create ENIs.  
  - `dms-cloudwatch-logs-role` (AWS-required) must exist in the account for logging to work.  
  - `dms-secrets-mgr-role` is **not created by this module**. If you use Secrets Manager, create it in your usage layer and pass the ARN.  

- **S3 Buckets**  
  - The module provisions two S3 buckets: one for assessment data and one for logs.  
  - Both buckets enforce TLS, versioning, SSE-KMS, and logging (OPA-compliant).  

- **CloudWatch Logs**  
  - A log group is created at `/aws/dms/${prefix_name}` with your KMS key and a retention period (`log_retention_days`, default 30).  
  - Replication tasks can log here when configured in `replication_settings`.
  