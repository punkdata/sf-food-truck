prefix_name = "labnoc-app1"

subnet_ids = [
  "subnet-12345678",
  "subnet-87654321"
]

vpc_security_group_ids = ["sg-abcdef123456"]

tags = {
  Environment = "dev"
  AIT         = "AIT-1234"
  Repo        = "https://github.com/org/infra-dms"
  Owner       = "platform-team"
}
