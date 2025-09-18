master_secret_name = "master_secret"

src_secret_key = "src_postgres"
tgt_secret_key = "tgt_postgres"

name_prefix                = "dms-multi"
subnet_ids                 = []
vpc_security_group_ids     = []
replication_instance_class = "dms.t3.medium"

tags = {
  Environment = "dev"
  Project     = "DMS"
  Owner       = "ADS Team"
}
