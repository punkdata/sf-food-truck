############################################
# REQUIRED VARIABLES
############################################

# Prefix for naming DMS resources (lowercase, alphanumeric + hyphens only).
prefix_name = "dev-dms"

# VPC where the DMS replication instance will run.
vpc_id = "vpc-xxxxxxxx"

# Subnets for the DMS replication subnet group.
subnet_ids = [
  "subnet-aaaaaaaa",
  "subnet-bbbbbbbb"
]

# Standardized tags required for all resources.
tags = {
  Environment = "dev"
  AIT         = "1234"
  Repo        = "dms-module"
  Owner       = "team@example.com"
}

# Existing RDS identifiers for the source and target databases.
# These are used to fetch host and dbname values via aws_db_instance data sources.
source_db_identifier = "my-source-rds"
target_db_identifier = "my-target-rds"
