# backend-setup.tf
# 创建远程后端基础设施
#
# 本文件创建：
# 1. S3 Bucket - 存储 Terraform State
# 2. DynamoDB Table - 提供 State Locking
#
# 注意：这些资源本身使用 Local State（鸡生蛋问题）
# 在生产环境中，通常使用 CloudFormation 或手动创建这些资源。

# -----------------------------------------------------------------------------
# Random ID - 确保 Bucket 名称唯一
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket - State 存储
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-${random_id.suffix.hex}"

  # 防止意外删除
  # 在学习环境中注释掉，生产环境应启用
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Name    = "Terraform State Bucket"
    Purpose = "terraform-state"
  }
}

# S3 Bucket 版本控制 - 保留 State 历史
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket 加密 - 保护敏感信息
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket 公共访问阻止 - 安全最佳实践
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DynamoDB Table - State Locking
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "tflock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"  # 按需付费，低成本
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "Terraform Lock Table"
    Purpose = "terraform-state-locking"
  }
}

# -----------------------------------------------------------------------------
# 使用说明
# -----------------------------------------------------------------------------
#
# 1. 运行 terraform apply 创建后端基础设施
#
# 2. 在其他项目中配置 backend：
#
#    terraform {
#      backend "s3" {
#        bucket         = "tfstate-xxxx"        # 使用 output 的值
#        key            = "project/terraform.tfstate"
#        region         = "ap-northeast-1"
#        dynamodb_table = "terraform-lock"
#        encrypt        = true
#      }
#    }
#
# 3. 运行 terraform init 迁移或初始化 State
#
# -----------------------------------------------------------------------------
