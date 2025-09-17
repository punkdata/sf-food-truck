# 1. KMS Key for Artifacts and Logs
resource "aws_kms_key" "codebuild_artifacts" {
  description         = "KMS key for CodeBuild artifacts and logs"
  enable_key_rotation = true
}

# 2. Encrypted S3 Bucket for Artifacts
resource "aws_s3_bucket" "codebuild_artifacts" {
  bucket        = "my-secure-codebuild-artifacts"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.codebuild_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.codebuild_artifacts.arn
    }
  }
}

# 3. IAM Role for CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "codebuild-secure-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "codebuild.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_basic" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess"
}

# 4. CodeBuild Project
resource "aws_codebuild_project" "secure_project" {
  name          = "secure-docker-builder"
  description   = "CodeBuild project with secure KMS artifacts"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type                = "S3"
    location            = aws_s3_bucket.codebuild_artifacts.bucket
    encryption_disabled = false
    encryption_key      = aws_kms_key.codebuild_artifacts.arn
    name                = "build-output.zip"
    packaging           = "ZIP"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false # ✅ Compliant
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/my-org/my-repo"
    buildspec = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      status             = "ENABLED"
      group_name         = "/aws/codebuild/secure-docker-builder"
      stream_name        = "build-logs"
      encryption_enabled = true
    }
  }

  cache {
    type           = "S3"
    location       = aws_s3_bucket.codebuild_artifacts.bucket
    modes          = ["LOCAL_CUSTOM_CACHE"]
    encryption_key = aws_kms_key.codebuild_artifacts.arn
  }
}
