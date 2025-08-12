locals {
  use_source_secret = (
    var.source_secrets_manager_arn != null &&
    var.source_secrets_manager_access_role_arn != null
  )
  use_target_secret = (
    var.target_secrets_manager_arn != null &&
    var.target_secrets_manager_access_role_arn != null
  )
  use_source_basic = (var.source_username != null && var.source_password != null)
  use_target_basic = (var.target_username != null && var.target_password != null)
}

# ───────── Replication subnet group ─────────
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.name_prefix}-dms-subnets"
  replication_subnet_group_description = "DMS subnets for ${var.name_prefix}"
  subnet_ids                           = var.replication_subnet_ids
  tags                                 = var.tags
}

# ───────── Replication instance ─────────
resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${var.name_prefix}-dms-repl"
  replication_instance_class  = var.replication_instance_class
  allocated_storage           = var.allocated_storage
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id
  vpc_security_group_ids      = var.replication_security_group_ids
  publicly_accessible         = false
  auto_minor_version_upgrade  = true
  kms_key_arn                 = var.replication_instance_kms_key_arn
  tags                        = var.tags

  engine_version              = var.engine_version
}

# ───────── Source endpoint ─────────
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.name_prefix}-src"
  endpoint_type = "source"
  engine_name   = var.source_engine_name
  server_name   = var.source_server_name
  port          = var.source_port
  database_name = var.source_database_name
  ssl_mode      = var.ssl_mode_source
  tags          = var.tags

  # Either Secrets Manager…
  secrets_manager_arn             = local.use_source_secret ? var.source_secrets_manager_arn : null
  secrets_manager_access_role_arn = local.use_source_secret ? var.source_secrets_manager_access_role_arn : null

  # …or inline credentials
  username = local.use_source_basic ? var.source_username : null
  password = local.use_source_basic ? var.source_password : null

  lifecycle {
    precondition {
      condition     = (local.use_source_secret && !local.use_source_basic) || (!local.use_source_secret && local.use_source_basic)
      error_message = "SOURCE endpoint: provide EITHER Secrets Manager (source_secrets_manager_arn + access_role_arn) OR username/password—exclusively."
    }
  }
}

# ───────── Target endpoint ─────────
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.name_prefix}-tgt"
  endpoint_type = "target"
  engine_name   = var.target_engine_name
  server_name   = var.target_server_name
  port          = var.target_port
  database_name = var.target_database_name
  ssl_mode      = var.ssl_mode_target
  tags          = var.tags

  # Either Secrets Manager…
  secrets_manager_arn             = local.use_target_secret ? var.target_secrets_manager_arn : null
  secrets_manager_access_role_arn = local.use_target_secret ? var.target_secrets_manager_access_role_arn : null

  # …or inline credentials
  username = local.use_target_basic ? var.target_username : null
  password = local.use_target_basic ? var.target_password : null

  lifecycle {
    precondition {
      condition     = (local.use_target_secret && !local.use_target_basic) || (!local.use_target_secret && local.use_target_basic)
      error_message = "TARGET endpoint: provide EITHER Secrets Manager (target_secrets_manager_arn + access_role_arn) OR username/password—exclusively."
    }
  }
}

# ───────── Replication task ─────────
resource "aws_dms_replication_task" "this" {
  replication_task_id      = "${var.name_prefix}-task"
  migration_type           = var.migration_type
  replication_instance_arn = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

  table_mappings            = var.table_mappings_json
  replication_task_settings = var.replication_task_settings_json

  tags = var.tags
}
