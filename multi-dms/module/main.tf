############################################
# VARIABLES
############################################

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix for naming DMS resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.prefix_name))
    error_message = "prefix_name must be lowercase letters, digits, and hyphens only, start/end with alphanumeric."
  }

  validation {
    condition     = !can(regex("--", var.prefix_name))
    error_message = "prefix_name cannot contain consecutive hyphens ('--')."
  }

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

variable "create_dms_roles" {
  description = "List of strict AWS DMS roles to create: dms-vpc-role, dms-cloudwatch-logs-role, dms-secrets-mgr-role."
  type        = list(string)
  default     = []
}

variable "iam_role_path" {
  description = "IAM path for created DMS roles."
  type        = string
  default     = "/service-role/"
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
}

############################################
# LOCALS & DATA
############################################

locals {
  name_prefix = var.prefix_name
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

############################################
# IAM — ASSUME ROLE POLICY
############################################

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

############################################
# IAM — STRICT ROLES (OPA-COMPLIANT)
############################################

resource "aws_iam_role" "strict" {
  for_each           = toset(var.create_dms_roles)
  name               = each.key
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

# dms-vpc-role
data "aws_iam_policy_document" "dms_vpc_role" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "dms_vpc_role" {
  count  = contains(var.create_dms_roles, "dms-vpc-role") ? 1 : 0
  name   = "${var.prefix_name}-dms-vpc-role-policy"
  policy = data.aws_iam_policy_document.dms_vpc_role.json
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role" {
  count      = contains(var.create_dms_roles, "dms-vpc-role") ? 1 : 0
  role       = aws_iam_role.strict["dms-vpc-role"].name
  policy_arn = aws_iam_policy.dms_vpc_role[0].arn
}

# dms-cloudwatch-logs-role
data "aws_iam_policy_document" "dms_cloudwatch_logs_role" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/dms/${local.name_prefix}:*"
    ]
  }
}

resource "aws_iam_policy" "dms_cloudwatch_logs_role" {
  count  = contains(var.create_dms_roles, "dms-cloudwatch-logs-role") ? 1 : 0
  name   = "${var.prefix_name}-dms-cloudwatch-logs-role-policy"
  policy = data.aws_iam_policy_document.dms_cloudwatch_logs_role.json
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role" {
  count      = contains(var.create_dms_roles, "dms-cloudwatch-logs-role") ? 1 : 0
  role       = aws_iam_role.strict["dms-cloudwatch-logs-role"].name
  policy_arn = aws_iam_policy.dms_cloudwatch_logs_role[0].arn
}

# dms-secrets-mgr-role
data "aws_iam_policy_document" "dms_secrets_mgr_role" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "dms_secrets_mgr_role" {
  count  = contains(var.create_dms_roles, "dms-secrets-mgr-role") ? 1 : 0
  name   = "${var.prefix_name}-dms-secrets-mgr-role-policy"
  policy = data.aws_iam_policy_document.dms_secrets_mgr_role.json
}

resource "aws_iam_role_policy_attachment" "dms_secrets_mgr_role" {
  count      = contains(var.create_dms_roles, "dms-secrets-mgr-role") ? 1 : 0
  role       = aws_iam_role.strict["dms-secrets-mgr-role"].name
  policy_arn = aws_iam_policy.dms_secrets_mgr_role[0].arn
}

############################################
# IAM — EXECUTION ROLE (CLEANED)
############################################

resource "aws_iam_role" "dms_execution_role" {
  name               = "${var.prefix_name}-dms-execution-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

data "aws_iam_policy_document" "dms_execution" {
  # Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/dms/${local.name_prefix}:*"
    ]
  }

  # Secrets
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  # S3
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.assessment.arn,
      "${aws_s3_bucket.assessment.arn}/*",
      aws_s3_bucket.assessment_logs.arn,
      "${aws_s3_bucket.assessment_logs.arn}/*"
    ]
  }

  # KMS
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_policy" "dms_execution" {
  name   = "${var.prefix_name}-dms-execution-role-policy"
  policy = data.aws_iam_policy_document.dms_execution.json
}

resource "aws_iam_role_policy_attachment" "dms_execution" {
  role       = aws_iam_role.dms_execution_role.name
  policy_arn = aws_iam_policy.dms_execution.arn
}

############################################
# CLOUDWATCH LOG GROUP
############################################

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${local.name_prefix}"
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
  replication_subnet_group_id          = "${var.prefix_name}-dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS replication instance"
  subnet_ids                           = var.subnet_ids
  tags                                 = var.tags
  depends_on                           = [aws_iam_role.strict]
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${var.prefix_name}-dms-instance"
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

  endpoint_id                     = "${var.prefix_name}-${each.key}"
  endpoint_type                   = each.value.endpoint_type
  engine_name                     = each.value.engine_name
  secrets_manager_arn             = each.value.secrets_manager_arn
  secrets_manager_access_role_arn = aws_iam_role.strict["dms-secrets-mgr-role"].arn
  kms_key_arn                     = var.kms_key_arn
  ssl_mode                        = each.value.ssl_mode
  database_name                   = each.value.database_name
  tags                            = var.tags
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

output "s3_assessment_bucket_arn" {
  value = aws_s3_bucket.assessment.arn
}

output "s3_assessment_logs_bucket" {
  value = aws_s3_bucket.assessment_logs.bucket
}

output "s3_assessment_logs_bucket_arn" {
  value = aws_s3_bucket.assessment_logs.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.dms.name
}

output "replication_instance_id" {
  value = aws_dms_replication_instance.this.replication_instance_id
}

output "replication_instance_arn" {
  value = aws_dms_replication_instance.this.replication_instance_arn
}

output "execution_role_arn" {
  value = aws_iam_role.dms_execution_role.arn
}

output "strict_roles" {
  value = { for k, r in aws_iam_role.strict : k => r.arn }
}

output "secrets_policies" {
  description = "Map of attached Secrets Manager secret policies by key"
  value       = {}
}

output "endpoint_arns" {
  value = { for k, e in aws_dms_endpoint.this : k => e.endpoint_arn }
}
