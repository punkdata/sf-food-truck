# IAM Role for CodeBuild with least privilege
resource "aws_iam_role" "codebuild_role" {
  name = "sre-build-container-image-role"

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

# IAM Policy for CodeBuild to interact with ECR, KMS, and CloudWatch Logs
resource "aws_iam_policy" "codebuild_policy" {
  name        = "sre-build-container-image-policy"
  description = "Permissions for CodeBuild to interact with ECR and KMS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "${aws_kms_key.ecr_kms.arn}"
      }
    ]
  })
}

# Attach IAM Policy to CodeBuild Role
resource "aws_iam_role_policy_attachment" "attach_codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# CodeBuild Project to Build Docker Image and Push to ECR
resource "aws_codebuild_project" "sre_build_container_image" {
  name          = "sre-build-container-image"
  description   = "Builds Docker image and pushes to ECR"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.sre.repository_url
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/your-org/your-repo.git"
    buildspec = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/sre-build-container-image"
      stream_name = "build-log"
    }
  }

  tags = {
    Project = "sre-container"
  }
}
