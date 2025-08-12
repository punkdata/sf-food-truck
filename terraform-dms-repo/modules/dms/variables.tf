variable "name_prefix" {
  description = "Prefix for DMS resource names (e.g., workload-to-gov)"
  type        = string
}

variable "replication_subnet_ids" {
  description = "Private subnet IDs for the DMS replication subnet group"
  type        = list(string)
}

variable "replication_security_group_ids" {
  description = "Security group IDs attached to DMS replication instance ENIs"
  type        = list(string)
}

variable "replication_instance_kms_key_arn" {
  description = "Customer-managed KMS key ARN to encrypt the DMS replication instance"
  type        = string
}

variable "replication_instance_class" {
  description = "DMS replication instance class (e.g., dms.t3.medium)"
  type        = string
  default     = "dms.t3.medium"
}

variable "allocated_storage" {
  description = "Allocated storage (GB) for the DMS replication instance"
  type        = number
  default     = 50
}

variable "engine_version" {
  description = "Optional DMS engine version (omit to use AWS default)"
  type        = string
  default     = null
}

# ---- Source endpoint ----
variable "source_engine_name" {
  description = "Source engine name (e.g., postgres, mysql)"
  type        = string
}

variable "source_server_name" {
  description = "Source DB hostname or endpoint"
  type        = string
}

variable "source_port" {
  description = "Source DB port"
  type        = number
}

variable "source_database_name" {
  description = "Source database name"
  type        = string
}

variable "source_secrets_manager_arn" {
  description = "ARN of Secrets Manager secret for SOURCE endpoint (must contain username/password)"
  type        = string
  default     = null
}

variable "source_secrets_manager_access_role_arn" {
  description = "IAM role ARN that DMS assumes to read the SOURCE secret"
  type        = string
  default     = null
}

variable "source_username" {
  description = "SOURCE DB username (only if not using Secrets Manager)"
  type        = string
  default     = null
}

variable "source_password" {
  description = "SOURCE DB password (only if not using Secrets Manager)"
  type        = string
  sensitive   = true
  default     = null
}

# ---- Target endpoint ----
variable "target_engine_name" {
  description = "Target engine name (e.g., postgres, mysql)"
  type        = string
}

variable "target_server_name" {
  description = "Target DB hostname or endpoint"
  type        = string
}

variable "target_port" {
  description = "Target DB port"
  type        = number
}

variable "target_database_name" {
  description = "Target database name"
  type        = string
}

variable "target_secrets_manager_arn" {
  description = "ARN of Secrets Manager secret for TARGET endpoint (must contain username/password)"
  type        = string
  default     = null
}

variable "target_secrets_manager_access_role_arn" {
  description = "IAM role ARN that DMS assumes to read the TARGET secret"
  type        = string
  default     = null
}

variable "target_username" {
  description = "TARGET DB username (only if not using Secrets Manager)"
  type        = string
  default     = null
}

variable "target_password" {
  description = "TARGET DB password (only if not using Secrets Manager)"
  type        = string
  sensitive   = true
  default     = null
}

# ---- Task settings ----
variable "migration_type" {
  description = "Migration type: full-load | cdc | full-load-and-cdc"
  type        = string
  default     = "full-load"
}

variable "table_mappings_json" {
  description = "JSON string for table mappings"
  type        = string
  default     = jsonencode({
    rules = [{
      "rule-type"      = "selection",
      "rule-id"        = "1",
      "rule-name"      = "include-all",
      "object-locator" = { "schema-name" = "%", "table-name" = "%" },
      "rule-action"    = "include"
    }]
  })
}

variable "replication_task_settings_json" {
  description = "JSON string for replication task settings"
  type        = string
  default     = jsonencode({
    FullLoadSettings = {
      TargetTablePrepMode             = "DROP_AND_CREATE"
      StopTaskCachedChangesApplied    = false
      StopTaskCachedChangesNotApplied = false
    }
  })
}

variable "ssl_mode_source" {
  description = "SSL mode for SOURCE endpoint (none | require | verify-ca | verify-full)"
  type        = string
  default     = "require"
}

variable "ssl_mode_target" {
  description = "SSL mode for TARGET endpoint (none | require | verify-ca | verify-full)"
  type        = string
  default     = "require"
}

variable "tags" {
  description = "Tags to apply to DMS resources"
  type        = map(string)
  default     = {}
}
