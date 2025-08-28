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
