#########################################
# Provider
#########################################
provider "aws" {
  region = var.region
}

#########################################
# Read master secret
#########################################
data "aws_secretsmanager_secret" "dms_user" {
  name = var.master_secret_name
}

data "aws_secretsmanager_secret_version" "dms_user" {
  secret_id = data.aws_secretsmanager_secret.dms_user.id
}

locals {
  master_secret_data = jsondecode(data.aws_secretsmanager_secret_version.dms_user.secret_string)
}

#########################################
# Derived secrets for DMS
#########################################
resource "aws_secretsmanager_secret" "src" {
  name = "${var.name_prefix}${var.src_secret_key}-dms-secret"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "src" {
  secret_id     = aws_secretsmanager_secret.src.id
  secret_string = jsonencode(local.master_secret_data[var.src_secret_key])
}

resource "aws_secretsmanager_secret" "tgt" {
  name = "${var.name_prefix}${var.tgt_secret_key}-dms-secret"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tgt" {
  secret_id     = aws_secretsmanager_secret.tgt.id
  secret_string = jsonencode(local.master_secret_data[var.tgt_secret_key])
}

#########################################
# KMS CMK
#########################################
resource "aws_kms_key" "dms" {
  description             = "KMS CMK for DMS resources (${var.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "dms" {
  name          = "alias/${var.name_prefix}dms"
  target_key_id = aws_kms_key.dms.key_id
}

#########################################
# Premigration S3 bucket
#########################################
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "dms_assessment" {
  bucket = "${var.name_prefix}dms-assessment-${random_string.suffix.result}"
  tags   = var.tags
}

#########################################
# IAM roles for DMS
#########################################
data "aws_iam_policy_document" "dms_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Role to allow DMS to read Secrets
resource "aws_iam_role" "dms_secrets" {
  name               = "${var.name_prefix}dms-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_secrets_access" {
  name   = "${var.name_prefix}dms-secrets-access"
  role   = aws_iam_role.dms_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.src.arn,
          aws_secretsmanager_secret.tgt.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.dms.arn
      }
    ]
  })
}

# Role to allow DMS to write to S3
resource "aws_iam_role" "dms_s3" {
  name               = "${var.name_prefix}dms-s3-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_s3_access" {
  name   = "${var.name_prefix}dms-s3-access"
  role   = aws_iam_role.dms_s3.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.dms_assessment.arn,
          "${aws_s3_bucket.dms_assessment.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.dms.arn
      }
    ]
  })
}

# Role to allow DMS to write to CloudWatch Logs
resource "aws_iam_role" "dms_logs" {
  name               = "${var.name_prefix}dms-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  path               = var.iam_role_path
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_logs_access" {
  name   = "${var.name_prefix}dms-logs-access"
  role   = aws_iam_role.dms_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

#########################################
# DMS module usage
#########################################
module "dms" {
  source = "../" # path to your dms-module

  name_prefix                = var.name_prefix
  subnet_ids                 = var.subnet_ids
  vpc_security_group_ids     = var.vpc_security_group_ids
  replication_instance_class = var.replication_instance_class

  create_kms_key = false
  kms_key_arn    = aws_kms_key.dms.arn

  create_assessment_s3_bucket = false
  assessment_bucket_name      = aws_s3_bucket.dms_assessment.bucket

  source_endpoints = {
    src1 = {
      engine_name = "postgres"
      secrets_manager = {
        arn      = aws_secretsmanager_secret.src.arn
        role_arn = aws_iam_role.dms_secrets.arn
      }
    }
  }

  target_endpoints = {
    tgt1 = {
      engine_name = "postgres"
      secrets_manager = {
        arn      = aws_secretsmanager_secret.tgt.arn
        role_arn = aws_iam_role.dms_secrets.arn
      }
    }
  }

  replication_tasks = {
    full_load = {
      source_endpoint_id       = "src1"
      target_endpoint_id       = "tgt1"
      migration_type           = "full-load"
      table_mappings = {
        rules = [
          {
            "rule-type"      = "selection"
            "rule-id"        = "1"
            "rule-name"      = "1"
            "object-locator" = { "schema-name" = "public", "table-name" = "%" }
            "rule-action"    = "include"
          }
        ]
      }
      replication_task_settings = {
        TargetMetadata   = { SupportLobs = true }
        FullLoadSettings = { TargetTablePrepMode = "DO_NOTHING" }
      }
    }
  }

  assessments = {
    assess1 = {
      source_endpoint_id  = "src1"
      target_endpoint_id  = "tgt1"
      table_mappings = {
        rules = [
          {
            "rule-type"      = "selection"
            "rule-id"        = "1"
            "rule-name"      = "1"
            "object-locator" = { "schema-name" = "public", "table-name" = "%" }
            "rule-action"    = "include"
          }
        ]
      }
      assessment_settings = {
        EnableAssessmentRun = true
        RulesToEnable       = ["All"]
      }
    }
  }

  tags = var.tags
}
