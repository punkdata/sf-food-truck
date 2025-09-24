############################################
# DATA SOURCES
############################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

############################################
# VARIABLES
############################################

variable "prefix_name" {
  type        = string
  description = "Prefix for DMS resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for DMS instance"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for replication subnet group"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources. Must include Environment, AIT, Repo, Owner."
}

############################################
# SECURITY GROUP FOR DMS INSTANCE
############################################

resource "aws_security_group" "dms" {
  name        = "${var.prefix_name}-dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = var.vpc_id

  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Example ingress (Postgres)
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

############################################
# KMS POLICY DOCUMENT
############################################

data "aws_region" "current" {}

data "aws_iam_policy_document" "kms_dms" {
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.id}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "dms" {
  description             = "Customer managed KMS key for DMS and secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_dms.json
  tags                    = var.tags

  depends_on = [
    module.dms
  ]
}

resource "aws_kms_alias" "dms" {
  name          = "alias/${var.prefix_name}-dms-kms"
  target_key_id = aws_kms_key.dms.key_id
}

############################################
# SECRETS FOR ENDPOINTS
############################################

resource "aws_secretsmanager_secret" "source_pg" {
  name       = "${var.prefix_name}-srcpg"
  kms_key_id = aws_kms_key.dms.arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "source_pg" {
  secret_id = aws_secretsmanager_secret.source_pg.id
  secret_string = jsonencode({
    username = "dms_user"
    password = "CHANGEME"
    engine   = "postgres"
    host     = "source-db.example.com"
    port     = 5432
    dbname   = "sourcedb"
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
    username = "dms_user"
    password = "CHANGEME"
    engine   = "postgres"
    host     = "target-db.example.com"
    port     = 5432
    dbname   = "targetdb"
    sslmode  = "require"
  })
}

############################################
# SECRET POLICIES (OPA COMPLIANT)
############################################

resource "aws_secretsmanager_secret_policy" "source_pg" {
  secret_arn          = aws_secretsmanager_secret.source_pg.arn
  block_public_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowDMSRoleRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.source_pg.arn
        Principal = {
          AWS = module.dms.strict_roles["dms-secrets-mgr-role"]
        }
      }
    ]
  })

  depends_on = [module.dms]
}

resource "aws_secretsmanager_secret_policy" "target_pg" {
  secret_arn          = aws_secretsmanager_secret.target_pg.arn
  block_public_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowDMSRoleRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.target_pg.arn
        Principal = {
          AWS = module.dms.strict_roles["dms-secrets-mgr-role"]
        }
      }
    ]
  })

  depends_on = [module.dms]
}

############################################
# MODULE USAGE
############################################

module "dms" {
  source                 = "../modules/dms"
  prefix_name            = var.prefix_name
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.dms.id]
  kms_key_arn            = aws_kms_key.dms.arn

  create_dms_roles = [
    "dms-cloudwatch-logs-role",
    "dms-secrets-mgr-role"
  ]

  endpoints = {
    sourcepg = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      ssl_mode            = "require"
    }
    targetpg = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
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
            "rule-type" = "selection"
            "rule-id"   = "1"
            "rule-name" = "includeAll"
            "object-locator" = {
              "schema-name" = "%"
              "table-name"  = "%"
            }
            "rule-action" = "include"
          }
        ]
      })

      replication_settings = jsonencode({
        TargetMetadata = {
          TargetSchema = ""
          SupportLobs  = true
        }
        FullLoadSettings = {
          TargetTablePrepMode = "DROP_AND_CREATE"
        }
      })
    }

    cdc-task = {
      source_endpoint = "sourcepg"
      target_endpoint = "targetpg"
      migration_type  = "cdc"

      table_mappings = jsonencode({
        rules = [
          {
            "rule-type" = "selection"
            "rule-id"   = "2"
            "rule-name" = "cdcAll"
            "object-locator" = {
              "schema-name" = "%"
              "table-name"  = "%"
            }
            "rule-action" = "include"
          }
        ]
      })

      replication_settings = jsonencode({
        Logging = {
          EnableLogging = true
        }
        ChangeProcessingDdlHandlingPolicy = {
          HandleSourceTableDropped   = true
          HandleSourceTableTruncated = true
          HandleSourceTableAltered   = true
        }
      })
    }
  }

  tags = var.tags
}

############################################
# OUTPUTS
############################################

output "dms_outputs" {
  description = "Key outputs from the DMS module"
  value = {
    kms_key_arn                   = module.dms.kms_key_arn
    s3_assessment_bucket          = module.dms.s3_assessment_bucket
    s3_assessment_bucket_arn      = module.dms.s3_assessment_bucket_arn
    s3_assessment_logs_bucket     = module.dms.s3_assessment_logs_bucket
    s3_assessment_logs_bucket_arn = module.dms.s3_assessment_logs_bucket_arn
    cloudwatch_log_group          = module.dms.cloudwatch_log_group
    replication_instance_id       = module.dms.replication_instance_id
    replication_instance_arn      = module.dms.replication_instance_arn
    execution_role_arn            = module.dms.execution_role_arn
    strict_roles                  = module.dms.strict_roles
    endpoint_arns                 = module.dms.endpoint_arns
    replication_tasks             = module.dms.replication_tasks
    secrets_policies = {
      source_pg = aws_secretsmanager_secret_policy.source_pg.id
      target_pg = aws_secretsmanager_secret_policy.target_pg.id
    }
  }
}
