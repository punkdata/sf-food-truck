############################################
# VARIABLES
############################################

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix used to name DMS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the DMS replication instance will be deployed."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DMS replication subnet group."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources. Must include Environment, AIT, Repo, Owner."
  type        = map(string)
}

variable "source_db_identifier" {
  description = "RDS identifier for the source database."
  type        = string
}

variable "target_db_identifier" {
  description = "RDS identifier for the target database."
  type        = string
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

  # Example: allow PostgreSQL ingress
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.tags, {
    Name = "${var.prefix_name}-dms-sg"
  })
}

############################################
# DATA SOURCES — RDS LOOKUPS
############################################

data "aws_db_instance" "source" {
  db_instance_identifier = var.source_db_identifier
}

data "aws_db_instance" "target" {
  db_instance_identifier = var.target_db_identifier
}

############################################
# CREATE SECRETS FOR DMS ENDPOINTS
############################################

resource "aws_secretsmanager_secret" "source_pg" {
  name       = "${var.prefix_name}-srcpg"
  kms_key_id = module.dms.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "source_pg" {
  secret_id = aws_secretsmanager_secret.source_pg.id
  secret_string = jsonencode({
    username = "dms_user"
    password = "CHANGEME-PASSWORD" # Replace securely
    engine   = "postgres"
    host     = data.aws_db_instance.source.address
    port     = 5432
    dbname   = data.aws_db_instance.source.db_name
    sslmode  = "require"
  })
}

resource "aws_secretsmanager_secret" "target_pg" {
  name       = "${var.prefix_name}-tgtpg"
  kms_key_id = module.dms.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "target_pg" {
  secret_id = aws_secretsmanager_secret.target_pg.id
  secret_string = jsonencode({
    username = "dms_user"
    password = "CHANGEME-PASSWORD" # Replace securely
    engine   = "postgres"
    host     = data.aws_db_instance.target.address
    port     = 5432
    dbname   = data.aws_db_instance.target.db_name
    sslmode  = "require"
  })
}

############################################
# MODULE USAGE
############################################

module "dms" {
  source = "../.." # Adjust to module path

  prefix_name            = var.prefix_name
  subnet_ids             = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.dms.id]

  instance_class    = "dms.t3.medium"
  allocated_storage = 100
  multi_az          = false

  create_dms_roles = [
    "dms-vpc-role",
    "dms-cloudwatch-logs-role",
    "dms-secrets-mgr-role"
  ]

  log_retention_days = 14

  endpoints = {
    source_pg = {
      endpoint_type       = "source"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.source_pg.arn
      ssl_mode            = "require"
    }
    target_pg = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
      ssl_mode            = "require"
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
    kms_key_arn               = module.dms.kms_key_arn
    kms_alias                 = module.dms.kms_alias
    s3_assessment_bucket      = module.dms.s3_assessment_bucket
    s3_assessment_logs_bucket = module.dms.s3_assessment_logs_bucket
    cloudwatch_log_group      = module.dms.cloudwatch_log_group
    replication_instance      = module.dms.replication_instance_id
    replication_instance_arn  = module.dms.replication_instance_arn
    execution_role_arn        = module.dms.execution_role_arn
    strict_roles              = module.dms.strict_roles
    endpoint_arns             = module.dms.endpoint_arns
  }
}
