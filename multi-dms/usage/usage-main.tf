############################################
# VARIABLES
############################################

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix for naming DMS resources."
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

############################################
# SECURITY GROUP FOR DMS INSTANCE
############################################

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
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.tags, {
    Name = "${var.prefix_name}-dms-sg"
  })
}

############################################
# SECRETS FOR DMS ENDPOINTS
############################################

resource "aws_secretsmanager_secret" "source_pg" {
  name = "${var.prefix_name}-srcpg"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "source_pg" {
  secret_id = aws_secretsmanager_secret.source_pg.id

  secret_string = jsonencode({
    username = "dms_user"
    password = "testpassword123"
    engine   = "postgres"
    host     = "source-db.example.local"
    port     = 5432
    dbname   = "sourcedb"
  })
}

resource "aws_secretsmanager_secret" "target_pg" {
  name = "${var.prefix_name}-tgtpg"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "target_pg" {
  secret_id = aws_secretsmanager_secret.target_pg.id

  secret_string = jsonencode({
    username = "dms_user"
    password = "testpassword123"
    engine   = "postgres"
    host     = "target-db.example.local"
    port     = 5432
    dbname   = "targetdb"
  })
}

############################################
# MODULE USAGE
############################################

module "dms" {
  source = "../modules/dms"

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
    }
    target_pg = {
      endpoint_type       = "target"
      engine_name         = "postgres"
      secrets_manager_arn = aws_secretsmanager_secret.target_pg.arn
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
    s3_assessment_bucket      = module.dms.s3_assessment_bucket
    s3_assessment_logs_bucket = module.dms.s3_assessment_logs_bucket
    cloudwatch_log_group      = module.dms.cloudwatch_log_group
    replication_instance_id   = module.dms.replication_instance_id
    execution_role_arn        = module.dms.execution_role_arn
    strict_roles              = module.dms.strict_roles
    endpoint_arns             = module.dms.endpoint_arns
  }
}
