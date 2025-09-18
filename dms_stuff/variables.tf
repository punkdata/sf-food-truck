variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "The VPC ID where the DMS replication instance will live"
  type        = string
}

variable "master_secret_name" {
  description = "Name of the existing master secret (looked up by dms_user)"
  type        = string
}

variable "src_secret_key" {
  description = "Subkey inside master_secret for the source DB"
  type        = string
}

variable "tgt_secret_key" {
  description = "Subkey inside master_secret for the target DB"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DMS replication subnet group"
}

variable "replication_instance_class" {
  type        = string
  description = "DMS replication instance type (e.g., dms.t3.medium)"
}

variable "iam_role_path" {
  description = "Path for DMS IAM roles (e.g., /role/dms/)"
  type        = string
  default     = "/role/dms/"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to resources"
}
