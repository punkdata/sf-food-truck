provider "aws" {
  region = "us-west-2"
}

variable "prefix_name" {
  description = "Lowercase, hyphenized prefix used to name DMS resources (applies to instance, log group, S3, etc.)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.prefix_name))
    error_message = "prefix_name must be lowercase letters, digits, and hyphens only, and cannot start/end with a hyphen."
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

variable "vpc_id" {
  description = "VPC ID where the DMS replication instance and security group will be created."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DMS replication subnet group."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources (must include Environment, AIT, Repo, Owner)."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "AIT", "Repo", "Owner"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, AIT, Repo, and Owner."
  }
}


provider "aws" {
  region = "us-east-1"
}

############################################
# SECURITY GROUP FOR DMS
############################################
resource "aws_security_group" "dms" {
  name        = "${var.prefix_name}-dms-sg"
  description = "Security group for DMS replication instance"
  vpc_id      = var.vpc_id

  # Safe default: allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Example: allow PostgreSQL ingress (replace with real DB CIDR or SG)
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
# MODULE USAGE
############################################
module "dms" {
  source = "../.."   # adjust path if needed

  prefix_name = var.prefix_name

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
  enable_versioning  = true

  tags = var.tags
}

############################################
# OUTPUTS FOR TESTING
############################################
output "dms_outputs" {
  description = "Key outputs from the DMS module"
  value = {
    kms_key_arn              = module.dms.kms_key_arn
    kms_alias                = module.dms.kms_alias
    s3_assessment_bucket     = module.dms.s3_assessment_bucket
    cloudwatch_log_group     = module.dms.cloudwatch_log_group
    replication_instance     = module.dms.replication_instance_id
    replication_instance_arn = module.dms.replication_instance_arn
    execution_role_arn       = module.dms.execution_role_arn
    strict_roles             = module.dms.strict_role_arns
  }
}
