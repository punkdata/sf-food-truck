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

variable "account_id" {
    default = "9000231757479"
}

data "aws_dynamodb_table_item" "test_aft_request"{
    table_name="test_aft_request"

    projection_expression = "email"
    key                   = <<KEY
    {
        "id": {"S": "${var.account_id}"}
    }
    KEY
}

data "aws_dynamodb_table_item" "test_aft_request_metadata"{
    table_name="test_aft_request_metadata"

    projection_expression = "custom_fields"
    key                   = <<KEY
    {
        "id": {"S": "${jsondecode(data.aws_dynamodb_table_item.test_aft_request.item)["email"].S}"}
    }
    KEY
}

output "var-account-id" {
  value="AccountID: ${var.account_id}"
}

output "aft_req_email" {
    value=jsondecode(data.aws_dynamodb_table_item.test_aft_request.item)["email"].S
  
}

output "aft_req_custom_fields" {

    value = jsondecode(jsondecode(data.aws_dynamodb_table_item.test_aft_request_metadata.item)["custom_fields"].S)["alias"]
}

