############################################
# DATA
############################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

############################################
# RANDOM SUFFIX
############################################
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false

  keepers = {
    prefix_name = var.prefix_name
  }
}

locals {
  prefix_name = "${var.prefix_name}-${random_string.suffix.result}"
}

############################################
# VARIABLES
############################################

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix for naming DMS resources."
  type        = string
  nullable    = false

  # Naming rules
  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.prefix_name))
    error_message = "prefix_name must contain only lowercase letters, digits, and hyphens, and must start/end with an alphanumeric character."
  }

  # No consecutive hyphens
  validation {
    condition     = !can(regex("--", var.prefix_name))
    error_message = "prefix_name cannot contain consecutive hyphens ('--')."
  }

  # Length check
  validation {
    condition     = length(var.prefix_name) <= 50
    error_message = "prefix_name must be 50 characters or fewer."
  }
}

variable "tags" {
  description = "Tags for all resources. Must include Environment, AIT, Repo, Owner."
  type        = map(string)
  nullable    = false

  validation {
    condition     = alltrue([for k in ["Environment", "AIT", "Repo", "Owner"] : contains(keys(var.tags), k)])
    error_message = "tags map must include Environment, AIT, Repo, and Owner."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key ARN for encryption (required)."
  type        = string
  nullable    = false
}

variable "dms_secrets_mgr_role_arn" {
  description = "ARN of the custom DMS Secrets Manager role (must be created outside this module)."
  type        = string
}

variable "dms_vpc_role_arn" {
  description = "ARN of the AWS DMS VPC role (must be created outside this module)."
  type        = string
  default     = null
}

variable "dms_cloudwatch_logs_role_arn" {
  description = "ARN of the AWS DMS CloudWatch Logs role (must be created outside this module)."
  type        = string
  default     = null
}


variable "log_retention_days" {
  description = "Retention in days for CloudWatch Logs."
  type        = number
  default     = 30
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DMS replication subnet group."
  type        = list(string)
  nullable    = false
}

variable "vpc_security_group_ids" {
  description = "Security groups for the replication instance."
  type        = list(string)
  default     = []
}

variable "instance_class" {
  description = "Replication instance class."
  type        = string
  default     = "dms.t3.medium"
}

variable "allocated_storage" {
  description = "Replication instance storage in GB."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Multi-AZ deployment."
  type        = bool
  default     = false
}

variable "endpoints" {
  description = <<EOT
Map of DMS endpoints.
Each value must include:
- endpoint_type       = "source" or "target"
- engine_name         = e.g., "postgres"
- secrets_manager_arn = ARN of a Secrets Manager secret containing DB creds
- database_name       = name of the database
Optional:
- ssl_mode            = "require" (default), or stronger ("verify-ca", "verify-full")
EOT
  type = map(object({
    endpoint_type       = string
    engine_name         = string
    secrets_manager_arn = string
    database_name       = string
    ssl_mode            = optional(string, "require")
  }))
  default  = {}
  nullable = false

  # Validate endpoint keys (naming rules)
  validation {
    condition = alltrue([
      for k in keys(var.endpoints) :
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", k))
    ])
    error_message = "Endpoint keys must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and must not end with a hyphen."
  }

  # Validate endpoint keys (length ≤ 255 with prefix)
  validation {
    condition = alltrue([
      for k in keys(var.endpoints) :
      length("${local.prefix_name}-${k}") <= 255
    ])
    error_message = "Endpoint ID (prefix_name + random suffix + endpoint key) must not exceed 255 characters."
  }

  # Validate endpoint_type values
  validation {
    condition = alltrue([
      for e in values(var.endpoints) :
      contains(["source", "target"], e.endpoint_type)
    ])
    error_message = "endpoints[*].endpoint_type must be either 'source' or 'target'."
  }
}

variable "replication_tasks" {
  description = <<EOT
Map of DMS replication tasks.
Each value must include:
- source_endpoint (must match a key in endpoints)
- target_endpoint (must match a key in endpoints)
- migration_type  (full-load, cdc, full-load-and-cdc)
- table_mappings  (JSON string)
Optional:
- replication_settings (JSON string)
EOT
  type = map(object({
    source_endpoint      = string
    target_endpoint      = string
    migration_type       = string
    table_mappings       = string
    replication_settings = optional(string)
  }))
  default  = {}
  nullable = false

  # Validate replication task keys (naming rules)
  validation {
    condition = alltrue([
      for k in keys(var.replication_tasks) :
      can(regex("^[a-z][a-z0-9-]*$", k))
    ])
    error_message = "Replication task keys must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (no underscores)."
  }

  # Validate replication task keys (length ≤ 255 with prefix)
  validation {
    condition = alltrue([
      for k in keys(var.replication_tasks) :
      length("${local.prefix_name}-${k}") <= 255
    ])
    error_message = "Replication task ID (prefix_name + random suffix + task key) must not exceed 255 characters."
  }

  # Validate migration_type values
  validation {
    condition = alltrue([
      for t in values(var.replication_tasks) :
      contains(["full-load", "cdc", "full-load-and-cdc"], t.migration_type)
    ])
    error_message = "replication_tasks[*].migration_type must be one of: full-load, cdc, or full-load-and-cdc."
  }

  # Validate endpoint references exist
  validation {
    condition = alltrue([
      for t in values(var.replication_tasks) :
      contains(keys(var.endpoints), t.source_endpoint) &&
      contains(keys(var.endpoints), t.target_endpoint)
    ])
    error_message = "Each replication task must reference valid source_endpoint and target_endpoint keys defined in var.endpoints."
  }

  # Validate table_mappings is valid JSON
  validation {
    condition = alltrue([
      for t in values(var.replication_tasks) :
      can(jsondecode(t.table_mappings))
    ])
    error_message = "replication_tasks[*].table_mappings must be valid JSON."
  }

  # Validate replication_settings is valid JSON (if provided)
  validation {
    condition = alltrue([
      for t in values(var.replication_tasks) :
      t.replication_settings == null || can(jsondecode(t.replication_settings))
    ])
    error_message = "replication_tasks[*].replication_settings must be valid JSON if provided."
  }
}

############################################
# CLOUDWATCH LOG GROUP
############################################

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${local.prefix_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

############################################
# S3 BUCKETS
############################################

resource "aws_s3_bucket" "assessment" {
  bucket        = "${var.prefix_name}-dms-assessments"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "assessment_policy" {
  statement {
    sid     = "EnforceTLSRequestsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.assessment.arn,
      "${aws_s3_bucket.assessment.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  policy = data.aws_iam_policy_document.assessment_policy.json
}

resource "aws_s3_bucket" "assessment_logs" {
  bucket        = "${var.prefix_name}-dms-assessments-logs"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assessment_logs" {
  bucket = aws_s3_bucket.assessment_logs.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "assessment_logs_policy" {
  statement {
    sid     = "EnforceTLSRequestsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.assessment_logs.arn,
      "${aws_s3_bucket.assessment_logs.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "assessment_logs" {
  bucket = aws_s3_bucket.assessment_logs.id
  policy = data.aws_iam_policy_document.assessment_logs_policy.json
}

# Logging on assessment bucket
resource "aws_s3_bucket_logging" "assessment" {
  bucket        = aws_s3_bucket.assessment.id
  target_bucket = aws_s3_bucket.assessment_logs.id
  target_prefix = "log/"
}

# Logging on logs bucket (self-logging, OPA compliant)
resource "aws_s3_bucket_logging" "assessment_logs" {
  bucket        = aws_s3_bucket.assessment_logs.id
  target_bucket = aws_s3_bucket.assessment_logs.id
  target_prefix = "log/"
}

# Versioning
resource "aws_s3_bucket_versioning" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "assessment_logs" {
  bucket = aws_s3_bucket.assessment_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

############################################
# DMS REPLICATION
############################################

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${local.prefix_name}-dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS replication instance"
  subnet_ids                           = var.subnet_ids
  tags                                 = var.tags
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${local.prefix_name}-dms-instance"
  replication_instance_class  = var.instance_class
  allocated_storage           = var.allocated_storage
  multi_az                    = var.multi_az
  vpc_security_group_ids      = var.vpc_security_group_ids
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id
  kms_key_arn                 = var.kms_key_arn
  publicly_accessible         = false
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  tags                        = var.tags
}

############################################
# DMS ENDPOINTS
############################################

resource "aws_dms_endpoint" "this" {
  for_each = var.endpoints

  endpoint_id                     = "${local.prefix_name}-${each.key}"
  endpoint_type                   = each.value.endpoint_type
  engine_name                     = each.value.engine_name
  secrets_manager_arn             = each.value.secrets_manager_arn
  secrets_manager_access_role_arn = var.dms_secrets_mgr_role_arn
  kms_key_arn                     = var.kms_key_arn
  ssl_mode                        = each.value.ssl_mode
  database_name                   = each.value.database_name
  tags                            = var.tags
}

############################################
# DMS REPLICATION TASKS
############################################

resource "aws_dms_replication_task" "this" {
  for_each = var.replication_tasks

  replication_task_id       = "${local.prefix_name}-${each.key}"
  migration_type            = each.value.migration_type
  replication_instance_arn  = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.this[each.value.source_endpoint].endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.this[each.value.target_endpoint].endpoint_arn
  table_mappings            = each.value.table_mappings
  replication_task_settings = each.value.replication_settings

  tags = var.tags
}

############################################
# OUTPUTS
############################################

output "kms_key_arn" {
  value = var.kms_key_arn
}

output "s3_assessment_bucket" {
  value = aws_s3_bucket.assessment.bucket
}

output "s3_assessment_logs_bucket" {
  value = aws_s3_bucket.assessment_logs.bucket
}
output "s3_assessment_bucket_arn" {
  description = "ARN of the assessment S3 bucket"
  value       = aws_s3_bucket.assessment.arn
}

output "s3_assessment_logs_bucket_arn" {
  description = "ARN of the assessment logs S3 bucket"
  value       = aws_s3_bucket.assessment_logs.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.dms.name
}

output "dms_secrets_mgr_role_arn" {
  value       = var.dms_secrets_mgr_role_arn
  description = "DMS Secrets Manager role ARN passed into the module."
}

output "dms_vpc_role_arn" {
  value       = var.dms_vpc_role_arn
  description = "DMS VPC role ARN passed into the module."
}

output "dms_cloudwatch_logs_role_arn" {
  value       = var.dms_cloudwatch_logs_role_arn
  description = "DMS CloudWatch Logs role ARN passed into the module."
}

output "replication_instance_id" {
  value = aws_dms_replication_instance.this.replication_instance_id
}

output "replication_instance_arn" {
  value = aws_dms_replication_instance.this.replication_instance_arn
}

output "endpoint_arns" {
  value = { for k, e in aws_dms_endpoint.this : k => e.endpoint_arn }
}

output "replication_tasks" {
  description = "Map of replication task details by key"
  value = {
    for k, t in aws_dms_replication_task.this :
    k => {
      id  = t.replication_task_id
      arn = t.replication_task_arn
    }
  }
}

