  ############################################
  # CircleCI Job example
  ############################################

  jobs:
  package-lambdas:
    executor: python-executor
    working_directory: ~/project
    steps:
      - checkout

      - run:
          name: Prepare environment
          command: |
            sudo apt-get update -y && sudo apt-get install -y zip jq
            python --version
            pip install --upgrade pip

      # Optional: install Lambda dependencies into each function dir
      - run:
          name: Install Lambda dependencies (optional)
          command: |
            if [ -f lambda_rotation/requirements.txt ]; then
              pip install -r lambda_rotation/requirements.txt -t lambda_rotation/
            fi
            if [ -f lambda_monitor/requirements.txt ]; then
              pip install -r lambda_monitor/requirements.txt -t lambda_monitor/
            fi

      # Package rotation Lambda
      - run:
          name: Package rotation Lambda
          command: |
            cd lambda_rotation
            zip -r ../lambda_rotation.zip . -x "*.pyc" "__pycache__/*"
            cd ..
            echo "Created lambda_rotation.zip"
            sha256sum lambda_rotation.zip > lambda_rotation.zip.sha256

      # Package monitor Lambda
      - run:
          name: Package monitor Lambda
          command: |
            cd lambda_monitor
            zip -r ../lambda_monitor.zip . -x "*.pyc" "__pycache__/*"
            cd ..
            echo "Created lambda_monitor.zip"
            sha256sum lambda_monitor.zip > lambda_monitor.zip.sha256

      # Store artifacts for inspection and downstream jobs
      - store_artifacts:
          path: lambda_rotation.zip
          destination: lambda_rotation.zip
      - store_artifacts:
          path: lambda_monitor.zip
          destination: lambda_monitor.zip
      - store_artifacts:
          path: lambda_rotation.zip.sha256
          destination: lambda_rotation.zip.sha256
      - store_artifacts:
          path: lambda_monitor.zip.sha256
          destination: lambda_monitor.zip.sha256

      # Persist to workspace for Terraform job
      - persist_to_workspace:
          root: .
          paths:
            - lambda_rotation.zip
            - lambda_monitor.zip
            - lambda_rotation.zip.sha256
            - lambda_monitor.zip.sha256
  workflows:
  version: 2
  build-and-deploy:
    jobs:
      - package-lambdas
  

###############################################################
# Terraform code
###############################################################

variable "project_name" {
  description = "Prefix for all resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "rds_master_secret_arn" {
  description = "ARN of existing RDS master secret in Secrets Manager"
  type        = string
}

variable "secret_kms_key_arn" {
  description = "KMS CMK ARN encrypting the RDS secret"
  type        = string
}

variable "lambda_env_kms_key_arn" {
  description = "KMS CMK ARN for encrypting Lambda environment variables"
  type        = string
}

variable "lambda_subnet_ids" {
  description = "Private subnet IDs (empty to skip VPC attach)"
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  description = "Security Group IDs (empty to skip VPC attach)"
  type        = list(string)
  default     = []
}

variable "rotation_cron_expression" {
  description = "Weekly cron schedule for rotation (UTC)"
  type        = string
  default     = "cron(0 5 ? * SUN *)" # every Sunday 05:00 UTC
}

variable "monitor_rate_expression" {
  description = "Interval for CloudTrail monitor"
  type        = string
  default     = "rate(5 minutes)"
}

variable "monitor_window_minutes" {
  description = "Minutes back to inspect CloudTrail"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Common resource tags"
  type = map(string)
  default = {
    Owner       = "DataPlatform"
    Environment = "prod"
    Purpose     = "RDS-Secret-Rotation-Monitor"
  }
}

locals {
  rotation_name = "${var.project_name}-rds-secret-rotation"
  monitor_name  = "${var.project_name}-rds-secret-monitor"
  rotation_log_group_name = "/aws/lambda/${local.rotation_name}"
  monitor_log_group_name  = "/aws/lambda/${local.monitor_name}"
}

###############################################################
# PACKAGE LAMBDAS (uses local code stored in GitHub checkout)
###############################################################

data "archive_file" "rotation_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_rotation"
  output_path = "${path.module}/lambda_rotation.zip"
}

data "archive_file" "monitor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_monitor"
  output_path = "${path.module}/lambda_monitor.zip"
}

###############################################################
# IAM ROLES AND POLICIES
###############################################################

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- Rotation Role ---
resource "aws_iam_role" "rotation" {
  name               = "${local.rotation_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

data "aws_iam_policy_document" "rotation_policy" {
  # CloudWatch logs
  statement {
    sid     = "CWLogs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  # Secrets Manager permissions (read/update only)
  statement {
    sid       = "SecretsRotate"
    actions   = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [var.rds_master_secret_arn]
  }

  # KMS permissions (encrypt/decrypt secret payloads)
  statement {
    sid       = "KMSSecretAccess"
    actions   = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [var.secret_kms_key_arn]
  }

  # RDS metadata read (optional for context)
  statement {
    sid       = "RDSDescribe"
    actions   = ["rds:DescribeDBInstances", "rds:DescribeDBClusters"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "rotation" {
  name   = "${local.rotation_name}-policy"
  policy = data.aws_iam_policy_document.rotation_policy.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "rotation_attach" {
  role       = aws_iam_role.rotation.name
  policy_arn = aws_iam_policy.rotation.arn
}

# --- Monitor Role ---
resource "aws_iam_role" "monitor" {
  name               = "${local.monitor_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

data "aws_iam_policy_document" "monitor_policy" {
  # Logs
  statement {
    sid     = "CWLogs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  # CloudTrail lookup access
  statement {
    sid       = "CloudTrailLookup"
    actions   = ["cloudtrail:LookupEvents"]
    resources = ["*"]
  }

  # Describe-only access to secret (no GetSecretValue)
  statement {
    sid       = "DescribeSecret"
    actions   = ["secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy"]
    resources = [var.rds_master_secret_arn]
  }
}

resource "aws_iam_policy" "monitor" {
  name   = "${local.monitor_name}-policy"
  policy = data.aws_iam_policy_document.monitor_policy.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "monitor_attach" {
  role       = aws_iam_role.monitor.name
  policy_arn = aws_iam_policy.monitor.arn
}

###############################################################
# LAMBDA FUNCTIONS
###############################################################

resource "aws_lambda_function" "rotation" {
  function_name    = local.rotation_name
  role             = aws_iam_role.rotation.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.9"
  memory_size      = 512
  timeout          = 300
  filename         = data.archive_file.rotation_zip.output_path
  source_code_hash = data.archive_file.rotation_zip.output_base64sha256
  kms_key_arn      = var.lambda_env_kms_key_arn
  tags             = var.tags

  environment {
    variables = {
      RDS_MASTER_SECRET_ARN = var.rds_master_secret_arn
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }
}

resource "aws_lambda_function" "monitor" {
  function_name    = local.monitor_name
  role             = aws_iam_role.monitor.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.9"
  memory_size      = 256
  timeout          = 60
  filename         = data.archive_file.monitor_zip.output_path
  source_code_hash = data.archive_file.monitor_zip.output_base64sha256
  kms_key_arn      = var.lambda_env_kms_key_arn
  tags             = var.tags

  environment {
    variables = {
      RDS_MASTER_SECRET_ARN         = var.rds_master_secret_arn
      CLOUDTRAIL_LOOKUP_MAX_RESULTS = "50"
      MONITOR_WINDOW_MINUTES        = tostring(var.monitor_window_minutes)
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }
}

###############################################################
# EVENTBRIDGE SCHEDULES
###############################################################

# Weekly rotation
resource "aws_cloudwatch_event_rule" "rotation" {
  name                = "${local.rotation_name}-rule"
  description         = "Weekly RDS secret rotation"
  schedule_expression = var.rotation_cron_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "rotation_target" {
  rule      = aws_cloudwatch_event_rule.rotation.name
  target_id = "rotation-lambda"
  arn       = aws_lambda_function.rotation.arn
}

resource "aws_lambda_permission" "rotation_invoke" {
  statement_id  = "AllowEventBridgeInvokeRotation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rotation.arn
}

# 5-minute monitor
resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${local.monitor_name}-rule"
  description         = "5-minute CloudTrail monitor for RDS secret"
  schedule_expression = var.monitor_rate_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "monitor_target" {
  rule      = aws_cloudwatch_event_rule.monitor.name
  target_id = "monitor-lambda"
  arn       = aws_lambda_function.monitor.arn
}

resource "aws_lambda_permission" "monitor_invoke" {
  statement_id  = "AllowEventBridgeInvokeMonitor"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor.arn
}

###############################################################
# CloudWatch Log Groups for Each Lambda
###############################################################

resource "aws_cloudwatch_log_group" "rotation" {
  name              = local.rotation_log_group_name
  retention_in_days = 400
  kms_key_id        = var.lambda_env_kms_key_arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "monitor" {
  name              = local.monitor_log_group_name
  retention_in_days = 400
  kms_key_id        = var.lambda_env_kms_key_arn
  tags              = var.tags
}

# Ensure Lambdas depend on log groups
resource "aws_lambda_function" "rotation" {
  depends_on = [aws_cloudwatch_log_group.rotation]
}

resource "aws_lambda_function" "monitor" {
  depends_on = [aws_cloudwatch_log_group.monitor]
}

###############################################################
# CloudWatch Metric Filters for Transaction-Level Visibility
###############################################################

# Detect any secret access events in rotation logs
resource "aws_cloudwatch_log_metric_filter" "rotation_secret_access" {
  name           = "${local.rotation_name}-secret-access"
  log_group_name = aws_cloudwatch_log_group.rotation.name
  pattern        = "{ ($.event = \"GetSecretValue\") || ($.action = \"rotate_secret\") }"

  metric_transformation {
    name      = "RotationSecretAccessCount"
    namespace = "RDSPipeline"
    value     = "1"
  }
}

# Detect RDS connection or token generation activity in rotation logs
resource "aws_cloudwatch_log_metric_filter" "rotation_rds_connect" {
  name           = "${local.rotation_name}-rds-connect"
  log_group_name = aws_cloudwatch_log_group.rotation.name
  pattern        = "{ ($.event = \"rds_iam_auth\") || ($.action = \"generate_db_auth_token\") }"

  metric_transformation {
    name      = "RdsIamAuthCount"
    namespace = "RDSPipeline"
    value     = "1"
  }
}

# Detect monitoring events (access polling)
resource "aws_cloudwatch_log_metric_filter" "monitor_secret_access" {
  name           = "${local.monitor_name}-secret-access"
  log_group_name = aws_cloudwatch_log_group.monitor.name
  pattern        = "{ ($.event = \"GetSecretValue\") || ($.eventName = \"DescribeSecret\") }"

  metric_transformation {
    name      = "MonitoredSecretAccessCount"
    namespace = "RDSPipeline"
    value     = "1"
  }
}

###############################################################
# Alarms for Unusual or Excessive Activity
###############################################################

# Alarm if secrets accessed more than threshold within 10 minutes
resource "aws_cloudwatch_metric_alarm" "unauthorized_secret_access" {
  alarm_name          = "${var.project_name}-unauthorized-secret-access"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 600
  threshold           = 3
  metric_name         = "MonitoredSecretAccessCount"
  namespace           = "RDSPipeline"
  statistic           = "Sum"
  alarm_description   = "Triggers if RDS master secret accessed >3 times in 10 minutes"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}

###############################################################
# Outputs
###############################################################

output "rotation_log_group_name" {
  description = "CloudWatch log group for rotation Lambda"
  value       = aws_cloudwatch_log_group.rotation.name
}

output "monitor_log_group_name" {
  description = "CloudWatch log group for monitor Lambda"
  value       = aws_cloudwatch_log_group.monitor.name
}

output "rotation_lambda_arn" {
  value = aws_lambda_function.rotation.arn
}

output "monitor_lambda_arn" {
  value = aws_lambda_function.monitor.arn
}

output "rotation_schedule_arn" {
  value = aws_cloudwatch_event_rule.rotation.arn
}

output "monitor_schedule_arn" {
  value = aws_cloudwatch_event_rule.monitor.arn
}
