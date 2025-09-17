# KMS key for ECR encryption
resource "aws_kms_key" "ecr_kms" {
  description         = "KMS key for ECR encryption"
  enable_key_rotation = true
}

# ECR repository with tag immutability and KMS encryption
resource "aws_ecr_repository" "sre" {
  name = "sre-container-image-repo"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_kms.arn
  }

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name        = "sre-container-image-repo"
    Environment = "Dev"
  }
}

# Lifecycle policy to clean untagged images
data "aws_ecr_lifecycle_policy_document" "ecr" {
  rule {
    priority    = 1
    description = "Expire untagged images after 30 days"

    selection {
      tag_status   = "untagged"
      count_type   = "sinceImagePushed"
      count_unit   = "days"
      count_number = 30
    }

    action {
      type = "expire"
    }
  }
}

resource "aws_ecr_lifecycle_policy" "ecr" {
  repository = aws_ecr_repository.sre.name
  policy     = data.aws_ecr_lifecycle_policy_document.ecr.json
}

# Enable enhanced scanning
resource "aws_ecr_registry_scanning_configuration" "registry" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
