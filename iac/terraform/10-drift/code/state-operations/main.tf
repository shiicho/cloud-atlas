# main.tf
# State 操作演练 - S3 Buckets
# =============================================================================
#
# 本文件创建多个 S3 Bucket，用于演练 State 操作命令：
#   - terraform state list
#   - terraform state show
#   - terraform state mv
#   - terraform state rm
#   - terraform apply -replace
#
# 使用场景:
#   1. terraform apply 创建资源
#   2. terraform state list 查看资源
#   3. terraform state mv 重命名资源
#   4. terraform state rm 取消管理
#   5. terraform apply -replace 强制重建
#
# =============================================================================

# -----------------------------------------------------------------------------
# Random ID - 生成唯一后缀
# -----------------------------------------------------------------------------
# S3 Bucket 名称必须全球唯一

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # 生成唯一的 bucket 名称前缀
  bucket_prefix = "demo-${random_id.suffix.hex}"
}

# -----------------------------------------------------------------------------
# S3 Bucket: logs
# -----------------------------------------------------------------------------
# 这个 bucket 将用于演示 state mv（重命名）

resource "aws_s3_bucket" "logs" {
  bucket = "${local.bucket_prefix}-logs"

  tags = {
    Name        = "Logs Bucket"
    Purpose     = "Application logs"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket: data
# -----------------------------------------------------------------------------
# 这个 bucket 将用于演示 state rm（取消管理）

resource "aws_s3_bucket" "data" {
  bucket = "${local.bucket_prefix}-data"

  tags = {
    Name        = "Data Bucket"
    Purpose     = "Application data"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket: backup
# -----------------------------------------------------------------------------
# 这个 bucket 将用于演示 -replace（强制重建）

resource "aws_s3_bucket" "backup" {
  bucket = "${local.bucket_prefix}-backup"

  tags = {
    Name        = "Backup Bucket"
    Purpose     = "Backup storage"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# 演练说明
# -----------------------------------------------------------------------------
#
# 1. state mv 演练：
#    terraform state mv aws_s3_bucket.logs aws_s3_bucket.log_bucket
#    然后修改代码中的资源名称
#
# 2. state rm 演练：
#    terraform state rm aws_s3_bucket.data
#    terraform state rm aws_s3_bucket_versioning.data
#    资源仍在 AWS 中，但 Terraform 不再管理
#
# 3. -replace 演练：
#    terraform apply -replace="aws_s3_bucket.backup"
#    强制删除并重新创建 bucket（注意：bucket 必须为空）
#
# -----------------------------------------------------------------------------
