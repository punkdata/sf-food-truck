##############################################
# Example: Postgres → Postgres with Secrets Manager
# and IAM roles created inline (no separate module)
##############################################

# Fill these in via tfvars or environment
variable "replication_subnet_ids" { type = list(string) }
variable "replication_security_group_ids" { type = list(string) }
variable "replication_instance_kms_key_arn" { type = string }

variable "source_server_name" { type = string }
variable "source_database_name" { type = string }
variable "source_secret_arn" { type = string }
variable "source_secret_kms_arn" { type = string }

variable "target_server_name" { type = string }
variable "target_database_name" { type = string }
variable "target_secret_arn" { type = string }
variable "target_secret_kms_arn" { type = string }

locals {
  name_prefix = "workload-to-gov"
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    App         = "data-migration"
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# -----------------------------
# Required IAM roles for DMS to read Secrets
# -----------------------------
# DMS service can assume these roles to read exactly one secret each.
resource "aws_iam_role" "dms_source_secret_access" {
  name = "${local.name_prefix}-source-secret-access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "dms.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role" "dms_target_secret_access" {
  name = "${local.name_prefix}-target-secret-access"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "dms.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

# Least-privilege inline policies: each role can read ONE secret and decrypt its CMK
resource "aws_iam_role_policy" "src_secret_policy" {
  name = "${local.name_prefix}-src-secret-policy"
  role = aws_iam_role.dms_source_secret_access.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "ReadSourceSecret",
        Effect: "Allow",
        Action: ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
        Resource: var.source_secret_arn
      },
      {
        Sid: "DecryptSourceSecret",
        Effect: "Allow",
        Action: ["kms:Decrypt","kms:DescribeKey"],
        Resource: var.source_secret_kms_arn,
        Condition: {
          "ForAnyValue:StringEquals": {
            "kms:ViaService": "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "tgt_secret_policy" {
  name = "${local.name_prefix}-tgt-secret-policy"
  role = aws_iam_role.dms_target_secret_access.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "ReadTargetSecret",
        Effect: "Allow",
        Action: ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
        Resource: var.target_secret_arn
      },
      {
        Sid: "DecryptTargetSecret",
        Effect: "Allow",
        Action: ["kms:Decrypt","kms:DescribeKey"],
        Resource: var.target_secret_kms_arn,
        Condition: {
          "ForAnyValue:StringEquals": {
            "kms:ViaService": "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# -----------------------------
# DMS: instance, endpoints, task
# -----------------------------
module "dms" {
  source = "../../modules/dms"

  name_prefix                        = local.name_prefix
  replication_subnet_ids             = var.replication_subnet_ids
  replication_security_group_ids     = var.replication_security_group_ids
  replication_instance_kms_key_arn   = var.replication_instance_kms_key_arn

  replication_instance_class         = "dms.t3.medium"
  allocated_storage                  = 50

  # Source (Secrets Manager)
  source_engine_name                 = "postgres"
  source_server_name                 = var.source_server_name
  source_port                        = 5432
  source_database_name               = var.source_database_name
  source_secrets_manager_arn         = var.source_secret_arn
  source_secrets_manager_access_role_arn = aws_iam_role.dms_source_secret_access.arn

  # Target (Secrets Manager)
  target_engine_name                 = "postgres"
  target_server_name                 = var.target_server_name
  target_port                        = 5432
  target_database_name               = var.target_database_name
  target_secrets_manager_arn         = var.target_secret_arn
  target_secrets_manager_access_role_arn = aws_iam_role.dms_target_secret_access.arn

  migration_type = "full-load"

  tags = local.tags
}
