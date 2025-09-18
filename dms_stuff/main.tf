provider "aws" {
  region = var.region
}

# Security Group for DMS
resource "aws_security_group" "dms_sg" {
  name        = "${var.name_prefix}dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Look up master secret
data "aws_secretsmanager_secret" "dms_user" {
  name = var.master_secret_name
}

data "aws_secretsmanager_secret_version" "dms_user" {
  secret_id = data.aws_secretsmanager_secret.dms_user.id
}

# Create derived source secret
resource "aws_secretsmanager_secret" "src" {
  name = "${var.name_prefix}${var.src_secret_key}-dms-secret"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "src" {
  secret_id     = aws_secretsmanager_secret.src.id
  secret_string = jsonencode(jsondecode(data.aws_secretsmanager_secret_version.dms_user.secret_string)[var.src_secret_key])
}

# Create derived target secret
resource "aws_secretsmanager_secret" "tgt" {
  name = "${var.name_prefix}${var.tgt_secret_key}-dms-secret"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tgt" {
  secret_id     = aws_secretsmanager_secret.tgt.id
  secret_string = jsonencode(jsondecode(data.aws_secretsmanager_secret_version.dms_user.secret_string)[var.tgt_secret_key])
}

# IAM role for DMS to access secrets
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
      }
    ]
  })
}

# Call the module
module "dms" {
  source = "../dms-module" # adjust path if needed

  name_prefix                = var.name_prefix
  subnet_ids                 = var.subnet_ids
  vpc_security_group_ids     = [aws_security_group.dms_sg.id]
  replication_instance_class = var.replication_instance_class

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
    }
  }

  premigration_assessments = {
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
