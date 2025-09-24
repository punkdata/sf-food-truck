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

- **`dms-secrets-mgr-role`** – **optional but required for Secrets Manager endpoints**.  
  This is **not provisioned by AWS by default**.  
  If you store database credentials in AWS Secrets Manager (recommended), DMS needs a role with `secretsmanager:GetSecretValue` it can assume.  
  By convention, most teams name it `dms-secrets-mgr-role`, but you may use a custom name if you pass the ARN when creating endpoints.  

⚠️ **Important**:  
- `dms-vpc-role` and `dms-cloudwatch-logs-role` must exist in the account before any DMS instance or task will succeed.  
- If you use Secrets Manager integration, you must also provision a `dms-secrets-mgr-role` (or equivalent).  

---

## Inputs

| Name | Type | Description | Default | Required |
|---|---|---|---|---|
| `prefix_name` | `string` | Lowercase, hyphenized prefix used for naming all DMS resources. | — | **Yes** |
| `subnet_ids` | `list(string)` | Subnet IDs for the DMS replication subnet group. | — | **Yes** |
| `vpc_security_group_ids` | `list(string)` | Security group IDs attached to the replication instance. | `[]` | No |
| `kms_key_arn` | `string` | Customer-managed KMS key ARN used for log group encryption and S3 buckets. | — | **Yes** |
| `endpoints` | `map(object({ endpoint_type=string, engine_name=string, secrets_manager_arn=string, database_name=string, ssl_mode=optional(string, "require") }))` | Map of DMS endpoints. `endpoint_type` is `"source"` or `"target"`. `engine_name` e.g. `"postgres"`. `ssl_mode` supports `"require"`, `"verify-ca"`, `"verify-full"`. | `{}` | **Yes** |
| `replication_tasks` | `map(object({ source_endpoint=string, target_endpoint=string, migration_type=string, table_mappings=string, replication_settings=optional(string) }))` | Map of replication tasks. `source_endpoint`/`target_endpoint` must match keys in `endpoints`. `migration_type` is one of `"full-load"`, `"cdc"`, `"full-load-and-cdc"`. `table_mappings`/`replication_settings` are JSON strings (inline or from `file(...)`). | `{}` | **Yes** |
| `tags` | `map(string)` | Resource tags. Must include `Environment`, `AIT`, `Repo`, `Owner`. | — | **Yes** |
| `iam_role_path` | `string` | IAM path for roles created by the module (e.g., execution role). | `"/service-role/"` | No |
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
| `execution_role_arn` | ARN of the DMS execution role. |
| `strict_roles` | Map of ARNs for any strict roles created. |
| `secrets_policies` | Map of attached Secrets Manager secret policies by key. |
| `endpoint_arns` | Map of DMS endpoint ARNs by key. |

---

## Usage

### Basic Example

```hcl
module "dms" {
  source                 = "github.com/your-org/terraform-aws-dms-module?ref=v1.6.0"
  prefix_name            = var.prefix_name
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.dms.id]
  kms_key_arn            = aws_kms_key.dms.arn

  endpoints = {
    sourcepg = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      database_name       = "sourcedb"
      ssl_mode            = "require"
    }
    targetpg = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
      database_name       = "targetdb"
      ssl_mode            = "require"
    }
  }

  replication_tasks = {
    full-load-task = {
      source_endpoint = "sourcepg"
      target_endpoint = "targetpg"
      migration_type  = "full-load"

      table_mappings = jsonencode({
        rules = [
          {
            "rule-type"      = "selection"
            "rule-id"        = "1"
            "rule-name"      = "includeAll"
            "object-locator" = {
              "schema-name" = "%"
              "table-name"  = "%"
            }
            "rule-action" = "include"
          }
        ]
      })
    }

    cdc-task = {
      source_endpoint      = "sourcepg"
      target_endpoint      = "targetpg"
      migration_type       = "cdc"
      table_mappings       = file("${path.module}/table-mappings/cdc.json")
      replication_settings = file("${path.module}/task-settings/cdc.json")
    }
  }

  tags = {
    Environment = "dev"
    AIT         = "dms-lab"
    Repo        = "infra-modules"
    Owner       = "team-x"
  }
}
```

📌 *See [JSON File Examples](#json-file-examples) below for sample `table-mappings.json` and `task-settings.json` content.*

---

### Robust Usage Example

This example shows a **full DMS build-out**, including KMS, security groups, Secrets Manager, and a replication task:

```hcl
# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS
resource "aws_kms_key" "dms" {
  description             = "Customer managed KMS key for DMS"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EnableRootAccount"
        Effect   = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
  tags = {
    Environment = "dev"
    AIT         = "dms-lab"
    Repo        = "infra-modules"
    Owner       = "team-x"
  }
}

resource "aws_kms_alias" "dms" {
  name          = "alias/demo-dms-kms"
  target_key_id = aws_kms_key.dms.key_id
}

# Security group
resource "aws_security_group" "dms" {
  name        = "demo-dms-sg"
  description = "DMS replication instance SG"
  vpc_id      = "vpc-1234567890abcdef0"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Environment = "dev"
    AIT         = "dms-lab"
    Repo        = "infra-modules"
    Owner       = "team-x"
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "source_pg" {
  name       = "demo-srcpg"
  kms_key_id = aws_kms_key.dms.arn
  tags       = aws_security_group.dms.tags
}
resource "aws_secretsmanager_secret_version" "source_pg" {
  secret_id = aws_secretsmanager_secret.source_pg.id
  secret_string = jsonencode({
    username = "src_user"
    password = "CHANGEME"
    engine   = "postgres"
    host     = "source-db.example.com"
    port     = 5432
    dbname   = "sourcedb"
    sslmode  = "require"
  })
}
resource "aws_secretsmanager_secret" "target_pg" {
  name       = "demo-tgtpg"
  kms_key_id = aws_kms_key.dms.arn
  tags       = aws_security_group.dms.tags
}
resource "aws_secretsmanager_secret_version" "target_pg" {
  secret_id = aws_secretsmanager_secret.target_pg.id
  secret_string = jsonencode({
    username = "tgt_user"
    password = "CHANGEME"
    engine   = "postgres"
    host     = "target-db.example.com"
    port     = 5432
    dbname   = "targetdb"
    sslmode  = "require"
  })
}

# Module usage
module "dms" {
  source                 = "github.com/your-org/terraform-aws-dms-module?ref=v1.6.0"
  prefix_name            = "demo-dms"
  subnet_ids             = ["subnet-1234567890abcdef0", "subnet-abcdef0123456789"]
  vpc_security_group_ids = [aws_security_group.dms.id]
  kms_key_arn            = aws_kms_key.dms.arn
  endpoints = {
    sourcepg = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      database_name       = "sourcedb"
      ssl_mode            = "require"
    }
    targetpg = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
      database_name       = "targetdb"
      ssl_mode            = "require"
    }
  }
  replication_tasks = {
    full-load-task = {
      source_endpoint = "sourcepg"
      target_endpoint = "targetpg"
      migration_type  = "full-load"
      table_mappings = jsonencode({
        rules = [
          {
            "rule-type"      = "selection"
            "rule-id"        = "1"
            "rule-name"      = "includeAll"
            "object-locator" = {
              "schema-name" = "%"
              "table-name"  = "%"
            }
            "rule-action" = "include"
          }
        ]
      })
    }
  }
  tags = aws_security_group.dms.tags
}
```

---

## JSON File Examples

In production, it’s often easier to manage complex task settings and mappings in external JSON files. Below are example snippets for reference.

### Table Mappings (`table-mappings/full-load.json`)

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

### Replication Settings (`task-settings/full-load.json`)

```json
{
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE",
    "StopTaskCachedChangesApplied": false,
    "StopTaskCachedChangesNotApplied": false
  },
  "Logging": {
    "EnableLogging": true
  }
}
```

### CDC Task Settings (`task-settings/cdc.json`)

```json
{
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true
  },
  "Logging": {
    "EnableLogging": true
  },
  "ControlTablesSettings": {
    "historyTimeslotInMinutes": 5,
    "historyTableEnabled": true
  }
}
```

---

## Gotchas

This module enforces AWS and OPA compliance rules. A few details to keep in mind:

- **Naming Constraints**  
  - `prefix_name` must be lowercase, hyphenized, and ≤ 50 characters.  
  - Replication task keys must start with a lowercase letter and only include lowercase letters, digits, and hyphens.  
  - Endpoint keys must also follow lowercase rules.  

- **KMS Key Usage**  
  - A customer-managed KMS key is required (`kms_key_arn`).  
  - The execution role gets `kms:Encrypt`, `kms:Decrypt`, and related permissions.  
  - Do not add KMS permissions in secret policies — only in the execution role.  

- **Secrets Manager Policies**  
  - Each secret must have a resource policy attached (OPA Secrets-Manager-4).  
  - `block_public_policy = true` is enforced (OPA Secrets-Manager-5).  
  - Policies are scoped to the DMS Secrets Manager role.  

- **Replication Tasks**  
  - Inline JSON (via `jsonencode`) is fine for small tests.  
  - Use external JSON files for real workloads.  
  - `migration_type` must be one of: `full-load`, `cdc`, `full-load-and-cdc`.  

- **Premigration Assessments**  
  - Terraform does not support running premigration assessments.  
  - These must be started manually in the AWS console.  
  - The module only provisions the infrastructure required.  

- **tfvars Usage**  
  - Always define `prefix_name`, `subnet_ids`, `kms_key_arn`, and `tags` in a `terraform.tfvars`.  
  - This prevents Terraform from hanging on missing required inputs.


# Milestones of Refactor

# ✅ Major DMS Module Refactor Milestones

## 1. Subnet Group Handling (2025-09-17)
- Removed `replication_subnet_group_name` variable.  
- Replaced with `subnet_ids` (list) and forced the module to always create a `replication_subnet_group`.  
- Updated **usage examples** and **README** to reflect the new required input.

---

## 2. KMS, IAM, and Service Principals Cleanup (2025-09-17 → 09-19)
- Introduced **`format()`-based locals** for AWS service principals (`logs`, `s3`, `dms`) to fix parsing errors.  
- Consolidated IAM policies into **consistent `aws_iam_policy_document` blocks**.  
- Updated KMS key policy to reference locals, preventing "missing resource identity" errors.  
- Result: a fully expanded `main.tf` baseline with OPA-compliant S3, CloudWatch, IAM, and KMS.

---

## 3. Replication Tasks & JSON Mappings (2025-09-18 → 09-19)
- Allowed **multiple replication tasks** via `replication_tasks` map.  
- Supported **inline JSON** or **file-based JSON** for table mappings, task settings, connection attributes.  
- Added **validation** for:
  - `migration_type` (`full-load`, `cdc`, `full-load-and-cdc`)  
  - `table_mappings` must not be null  
- Paused discussion on whether to provide **defaults** vs **require JSON files**.

---

## 4. Premigration Assessment Support (2025-09-18 → 09-19)
- Added `premigration_assessments` map.  
- Each assessment task is created as a separate resource.  
- Assessment settings can be passed inline JSON or file reference.

---

## 5. Secrets Manager & KMS Policy Fixes (2025-09-23 → 09-24)
- Fixed **KMS key policy** to allow Secrets Manager retrieval.  
- Added **IAM policy_document + attachment** for Secrets Manager (OPA compliance).  
- Validated that secrets resolution requires both KMS permissions and proper role trust.

---

## 6. Remove DMS Role Creation (2025-09-24 → 09-25)
- Decided **not to create** the following inside the module:
  - `dms-vpc-role` (AWS required, global)  
  - `dms-cloudwatch-logs-role` (AWS required, global)  
  - `dms-secrets-mgr-role` (custom, but can cause duplicates if module deployed multiple times)  
- Instead:  
  - Added variables `dms_vpc_role_arn`, `dms_cloudwatch_logs_role_arn`, `dms_secrets_mgr_role_arn`.  
  - Updated references in endpoints and replication instance to consume ARNs.  
  - Outputs now surface passed-in role ARNs.

---

# 📌 Current Status
- The module is **OPA-compliant**, **multi-task capable**, and **multi-endpoint capable**.  
- All IAM roles are now **externalized** to avoid duplication.  
- Usage examples, tfvars, and README need to be aligned to reflect these changes (passing in role ARNs instead of creating roles).
