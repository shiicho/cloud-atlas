# main.tf
# 主资源定义
#
# 本文件演示如何使用变量和 locals 创建资源。

# -----------------------------------------------------------------------------
# Random ID - 确保资源名称唯一
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket - 使用变量配置
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  # 使用 local 组合命名
  bucket = "${local.name_prefix}-${random_id.suffix.hex}"

  # 使用 local 统一标签
  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# S3 Bucket Versioning - 条件配置
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    # 使用变量控制是否启用
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Encryption - 条件配置
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  # 只有启用加密时才创建
  count = var.enable_encryption ? 1 : 0

  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Lifecycle - 使用 object 变量
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "app" {
  # 只有设置了生命周期天数时才创建
  count = local.lifecycle_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.app.id

  rule {
    id     = "cleanup-old-objects"
    status = "Enabled"

    expiration {
      days = local.lifecycle_days
    }

    filter {
      prefix = "logs/"
    }
  }
}

# -----------------------------------------------------------------------------
# 变量使用总结
# -----------------------------------------------------------------------------
#
# | 变量类型    | 使用示例                                |
# |-------------|----------------------------------------|
# | string      | bucket = "${var.project}-xxx"          |
# | number      | days = var.lifecycle_days              |
# | bool        | status = var.enable_versioning ? "Enabled" : "Disabled" |
# | list        | for ip in var.allowed_ips              |
# | map         | lookup(var.instance_types, var.env)    |
# | object      | var.bucket_config.versioning           |
# | locals      | local.name_prefix                      |
#
# -----------------------------------------------------------------------------
