############################################
# VARIABLES
############################################

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix for naming DMS resources (used in IDs, KMS alias, log group, S3 bucket)."
  type        = string

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
  description = <<EOT
Tags to apply to all resources.
Must include the following keys:
- Environment → lifecycle stage (dev/staging/prod)
- AIT         → business/application identifier
- Repo        → full URL of the code repository (e.g., https://github.com/org/repo-name)
- Owner       → responsible team or individual
EOT
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "AIT", "Repo", "Owner"] : contains(keys(var.tags), k)])
    error_message = "tags map must include Environment, AIT, Repo, and Owner."
  }
}

variable "create_dms_roles" {
  description = <<EOT
List of strict AWS DMS service roles to create.
If empty, the module assumes the roles already exist.

Available values:
- dms-vpc-role              → Required for DMS to create/manage ENIs in your VPC.
- dms-cloudwatch-logs-role  → Required for DMS to publish logs to CloudWatch Logs.
- dms-secrets-mgr-role      → Required for DMS to read connection details from AWS Secrets Manager.
EOT
  type    = list(string)
  default = []
}

variable "iam_role_path" {
  description = "IAM path for created DMS roles (OPA requires /service-role/ by default)."
  type        = string
  default     = "/service-role/"
}

variable "log_retention_days" {
  description = "Number of days to retain DMS CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 3653
    error_message = "log_retention_days must be between 7 and 3653 (inclusive)."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 assessment bucket."
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DMS replication subnet group."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to attach to the replication instance."
  type        = list(string)
  default     = []
}

variable "instance_class" {
  description = "DMS replication instance class."
  type        = string
  default     = "dms.t3.medium"
}

variable "allocated_storage" {
  description = "Allocated storage (in GB) for the DMS replication instance."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Launch DMS replication instance with Multi-AZ."
  type        = bool
  default     = false
}

############################################
# LOCALS & DATA
############################################

locals {
  name_prefix = "${var.prefix_name}-dms"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

############################################
# RANDOM SUFFIX
############################################

resource "random_string" "general_suffix" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

############################################
# KMS
############################################

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid     = "EnableRootAccountAdmin"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "dms" {
  description             = "Customer-managed CMK for AWS DMS components (instance, endpoints, logs, S3)."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json
  tags                    = var.tags
}

resource "aws_kms_alias" "dms" {
  name          = "alias/${local.name_prefix}-kms-${random_string.general_suffix.result}"
  target_key_id = aws_kms_key.dms.key_id
}

############################################
# IAM — STRICT AWS ROLES
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

# VPC Role
resource "aws_iam_role" "dms_vpc_role" {
  count              = contains(var.create_dms_roles, "dms-vpc-role") ? 1 : 0
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_vpc_role_policy" {
  count = aws_iam_role.dms_vpc_role.count
  name  = "${var.prefix_name}-dms-vpc-role-policy"
  role  = aws_iam_role.dms_vpc_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "ec2:Describe*",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute"
      ]
      Resource = "*"
    }]
  })
}

# CloudWatch Logs Role
resource "aws_iam_role" "dms_logs_role" {
  count              = contains(var.create_dms_roles, "dms-cloudwatch-logs-role") ? 1 : 0
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_logs_role_policy" {
  count = aws_iam_role.dms_logs_role.count
  name  = "${var.prefix_name}-dms-logs-role-policy"
  role  = aws_iam_role.dms_logs_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/dms/${local.name_prefix}:*"
    }]
  })
}

# Secrets Manager Role
resource "aws_iam_role" "dms_secrets_role" {
  count              = contains(var.create_dms_roles, "dms-secrets-mgr-role") ? 1 : 0
  name               = "dms-secrets-mgr-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_secrets_role_policy" {
  count = aws_iam_role.dms_secrets_role.count
  name  = "${var.prefix_name}-dms-secrets-role-policy"
  role  = aws_iam_role.dms_secrets_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "*"
    }]
  })
}

############################################
# IAM — CONSOLIDATED EXECUTION ROLE
############################################

resource "aws_iam_role" "dms_execution_role" {
  name               = "${var.prefix_name}-dms-execution-role-${random_string.general_suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_execution_role_policy" {
  name = "${var.prefix_name}-dms-execution-role-policy"
  role = aws_iam_role.dms_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # VPC Networking — must remain wildcard
      {
        Effect   = "Allow"
        Action   = [
          "ec2:Describe*",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute"
        ]
        Resource = "*"
      },
      # CloudWatch Logs — scoped
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.dms.arn}:*"
      },
      # Secrets Manager — scoped later when endpoints are added
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "*"
      },
      # S3 Assessment Bucket — scoped
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.assessment.arn,
          "${aws_s3_bucket.assessment.arn}/*"
        ]
      },
      # KMS CMK — scoped
      {
        Effect   = "Allow"
        Action   = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey"
        ]
        Resource = aws_kms_key.dms.arn
      }
    ]
  })
}

############################################
# CLOUDWATCH LOG GROUP
############################################

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.dms.arn
  tags              = var.tags
}

############################################
# S3 ASSESSMENT BUCKET
############################################

resource "aws_s3_bucket" "assessment" {
  bucket        = "${var.prefix_name}-dms-assessments-${random_string.general_suffix.result}"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.dms.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assessment" {
  bucket                  = aws_s3_bucket.assessment.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "assessment" {
  bucket = aws_s3_bucket.assessment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyUnencryptedUploads"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.assessment.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
        Principal = "*"
      },
      {
        Sid      = "DenyInsecureTransport"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.assessment.arn,
          "${aws_s3_bucket.assessment.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = false
          }
        }
        Principal = "*"
      }
    ]
  })
}

############################################
# DMS REPLICATION INSTANCE
############################################

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.prefix_name}-dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS replication instance (${var.prefix_name})"
  subnet_ids                           = var.subnet_ids
  tags                                 = var.tags
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${var.prefix_name}-dms-instance"
  replication_instance_class  = var.instance_class
  allocated_storage           = var.allocated_storage
  multi_az                    = var.multi_az
  vpc_security_group_ids      = var.vpc_security_group_ids
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id
  kms_key_arn                 = aws_kms_key.dms.arn
  publicly_accessible         = false
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  tags                        = var.tags
}

############################################
# CORE OUTPUTS
############################################

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS CMK for DMS."
  value       = aws_kms_key.dms.arn
}

output "kms_alias" {
  description = "Alias name of the KMS CMK."
  value       = aws_kms_alias.dms.name
}

output "s3_assessment_bucket" {
  description = "Name of the S3 bucket for DMS pre-migration assessments."
  value       = aws_s3_bucket.assessment.bucket
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch Log Group for DMS replication tasks."
  value       = aws_cloudwatch_log_group.dms.name
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance."
  value       = aws_dms_replication_instance.this.replication_instance_id
}

output "replication_instance_arn" {
  description = "ARN of the DMS replication instance."
  value       = aws_dms_replication_instance.this.replication_instance_arn
}

############################################
# IAM OUTPUTS
############################################

output "execution_role_arn" {
  description = "ARN of the consolidated DMS execution role."
  value       = aws_iam_role.dms_execution_role.arn
}

output "strict_role_arns" {
  description = "Map of strict AWS DMS roles created by this module (if any)."
  value = {
    vpc_role     = try(aws_iam_role.dms_vpc_role[0].arn, null)
    logs_role    = try(aws_iam_role.dms_logs_role[0].arn, null)
    secrets_role = try(aws_iam_role.dms_secrets_role[0].arn, null)
  }
}
