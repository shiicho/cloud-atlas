# =============================================================================
# S3 Bucket 模块 - 可复用组件
# =============================================================================
# 封装 S3 Bucket 创建的最佳实践
# 包含：版本控制、加密、生命周期、公共访问阻止
# =============================================================================

# -----------------------------------------------------------------------------
# 随机后缀
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket = "${var.bucket_prefix}-${var.environment}-${random_id.suffix.hex}"

  # 非 prod 环境允许强制删除
  force_destroy = var.environment != "prod"

  tags = merge(var.tags, {
    Name        = "${var.bucket_prefix}-${var.environment}"
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# 版本控制
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# -----------------------------------------------------------------------------
# 生命周期规则
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.lifecycle_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    expiration {
      days = var.lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# -----------------------------------------------------------------------------
# 服务端加密
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # bucket_key_enabled 仅适用于 aws:kms 加密，AES256 不需要此参数
  }
}

# -----------------------------------------------------------------------------
# 公共访问阻止
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
