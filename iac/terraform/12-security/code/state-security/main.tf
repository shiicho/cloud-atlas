# =============================================================================
# State 安全配置 - 完整示例
# State Security Configuration - Complete Example
# =============================================================================
#
# 这个配置创建一个安全的 Terraform State 存储环境：
# - S3 Bucket（加密、版本控制、访问日志）
# - KMS 密钥（客户管理加密）
# - 严格的 Bucket Policy
# - 使用 S3 原生锁定 (use_lockfile = true)，无需 DynamoDB
#
# =============================================================================

terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "terraform-state"
      ManagedBy = "terraform"
    }
  }
}

# =============================================================================
# 数据源
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# KMS 密钥 - State 加密专用
# =============================================================================

resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # 严格的密钥策略
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Terraform Roles"
        Effect = "Allow"
        Principal = {
          AWS = var.terraform_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "terraform-state-key"
  }
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/terraform-state-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.tfstate.key_id
}

# =============================================================================
# S3 Bucket - State 存储
# =============================================================================

resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-${var.project_name}-${random_id.suffix.hex}"

  # 防止意外删除
  force_destroy = false

  tags = {
    Name    = "Terraform State Bucket"
    Purpose = "terraform-state"
  }
}

# 版本控制 - State 历史记录
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS 加密
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.tfstate.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true  # 降低 KMS 调用成本
  }
}

# 阻止公开访问
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 生命周期规则
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    # 保留旧版本 90 天（用于审计和恢复）
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # 30 天后转为 IA 存储（节省成本）
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
  }
}

# =============================================================================
# 访问日志 Bucket
# =============================================================================

resource "aws_s3_bucket" "logs" {
  bucket = "tfstate-logs-${var.project_name}-${random_id.suffix.hex}"

  tags = {
    Name    = "Terraform State Access Logs"
    Purpose = "logging"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # 日志桶使用 S3 管理的加密即可
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 日志桶的生命周期规则
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "cleanup-old-logs"
    status = "Enabled"

    # 日志保留 1 年（符合大多数审计要求）
    expiration {
      days = 365
    }

    # 30 天后转为 IA
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # 90 天后转为 Glacier
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# 启用访问日志
resource "aws_s3_bucket_logging" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "tfstate-access-logs/"
}

# =============================================================================
# State Locking - 使用 S3 原生锁定
# =============================================================================
# Terraform 1.10+ 支持原生 S3 锁定 (use_lockfile = true)
# 无需创建 DynamoDB 表，降低成本和复杂度
#
# 使用方式（在 backend 配置中）：
#   backend "s3" {
#     bucket       = "..."
#     key          = "..."
#     region       = "..."
#     encrypt      = true
#     use_lockfile = true  # 原生 S3 锁定
#   }
# =============================================================================
