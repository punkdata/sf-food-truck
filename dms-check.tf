variable "create_dms_vpc_role" {
  type        = bool
  default     = true
}

data "aws_iam_role" "dms_vpc_role_existing" {
  count = var.create_dms_vpc_role ? 1 : 0
  name  = "dms-vpc-role"
}

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_vpc_role" {
  for_each = try(data.aws_iam_role.dms_vpc_role_existing[0].name, null) == null ? {
    "create" = "dms-vpc-role"
  } : {}

  name               = each.value
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = "/service-role/"

  tags = {
    ManagedBy  = "terraform"
    Compliance = "OPA"
    Purpose    = "DMSVpcRole"
  }
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy" {
  for_each   = aws_iam_role.dms_vpc_role
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

output "dms_vpc_role_arn" {
  value = coalesce(
    try(data.aws_iam_role.dms_vpc_role_existing[0].arn, null),
    try(values(aws_iam_role.dms_vpc_role)[0].arn, null)
  )
}


try this example 


variable "create_dms_roles" {
  type        = list(string)
  default     = []
  description = <<EOT
List of DMS IAM roles to create. By default, no roles are created.
Valid values you can specify are:
  - "dms-vpc-role"
  - "dms-cloudwatch-logs-role"
  - "dms-access-for-endpoint"
EOT
}

locals {
  dms_roles = {
    "dms-vpc-role"              = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
    "dms-cloudwatch-logs-role"  = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
    "dms-access-for-endpoint"   = "arn:aws:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
  }
}

# Trust policy (all DMS roles share this)
data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

# Create requested roles
resource "aws_iam_role" "dms_roles" {
  for_each = { for role, policy in local.dms_roles : role => policy if role in var.create_dms_roles }

  name               = each.key
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  path               = "/service-role/"

  tags = {
    ManagedBy  = "terraform"
    Compliance = "OPA"
    Purpose    = each.key
  }
}

# Attach correct AWS-managed policies
resource "aws_iam_role_policy_attachment" "dms_role_policies" {
  for_each   = aws_iam_role.dms_roles
  role       = each.value.name
  policy_arn = local.dms_roles[each.key]
}

# Output ARNs for created roles
output "dms_role_arns" {
  value = { for role, res in aws_iam_role.dms_roles : role => res.arn }
}
