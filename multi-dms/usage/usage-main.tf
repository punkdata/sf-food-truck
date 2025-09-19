provider "aws" {
  region = "us-east-1"
}

module "dms" {
  source = "../.."   # adjust path if needed

  prefix_name = "labnoc-app1"

  # Networking for replication instance
  subnet_ids             = ["subnet-12345678", "subnet-87654321"]
  vpc_security_group_ids = ["sg-abcdef123456"]

  # Replication instance settings
  instance_class    = "dms.t3.medium"
  allocated_storage = 100
  multi_az          = false

  # Optional: create AWS strict DMS service roles
  create_dms_roles = [
    "dms-vpc-role",
    "dms-cloudwatch-logs-role",
    "dms-secrets-mgr-role"
  ]

  # CloudWatch log retention
  log_retention_days = 90

  # S3 assessment bucket
  enable_versioning = true

  # Required tags
  tags = {
    Environment = "dev"
    AIT         = "Your_AIT"
    Repo        = "https://github.com/org/infra-dms"
    Owner       = "platform-team"
  }
}

output "dms_outputs" {
  description = "Key outputs from the DMS module"
  value = {
    kms_key_arn            = module.dms.kms_key_arn
    kms_alias              = module.dms.kms_alias
    s3_assessment_bucket   = module.dms.s3_assessment_bucket
    cloudwatch_log_group   = module.dms.cloudwatch_log_group
    replication_instance   = module.dms.replication_instance_id
    replication_instance_arn = module.dms.replication_instance_arn
    execution_role_arn     = module.dms.execution_role_arn
    strict_roles           = module.dms.strict_role_arns
  }
}
