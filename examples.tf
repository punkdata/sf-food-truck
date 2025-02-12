terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_dynamodb_table_item" "aft_request_metadata"{
    table_name="aft_request_metadata"

    projection_expression = "email"
    key = jsonencode({
        id = { S = var.account_id }
    })
}

data "aws_dynamodb_table_item" "aft_request"{
    table_name="aft_request"

    projection_expression = "custom_fields"
    key = jsonencode({
        id = { S = jsondecode(data.aws_dynamodb_table_item.aft_request_metadata.item)["email"].S }
      })
}

output "var-account-id" {
  value="AccountID: ${var.account_id}"
}

output "aft_req_email" {
    value=jsondecode(data.aws_dynamodb_table_item.aft_request_metadata.item)["email"].S
  
}

output "aft_req_custom_fields" {

    value = jsondecode(jsondecode(data.aws_dynamodb_table_item.aft_request.item)["custom_fields"].S)["alias"]
}

