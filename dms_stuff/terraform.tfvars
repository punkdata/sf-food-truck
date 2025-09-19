region = "us-east-1"
vpc_id = "vpc-12345678"

master_secret_name = "master_secret"
src_secret_key     = "src_postgres"
tgt_secret_key     = "tgt_postgres"

name_prefix                = "example-dms-"
subnet_ids                 = ["subnet-12345678", "subnet-abcdef12"]
replication_instance_class = "dms.t3.medium"

tags = {
  Environment = "dev"
  Project     = "DMS"
  Owner       = "ADS Team"
}
