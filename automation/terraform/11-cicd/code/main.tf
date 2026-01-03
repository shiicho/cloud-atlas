# main.tf
# CI/CD 示例资源
#
# 本文件创建一个简单的 S3 Bucket，用于演示 CI/CD 流程。
# 当你在 PR 中修改这些资源时，GitHub Actions 会自动：
# 1. 运行 terraform plan
# 2. 将 plan 结果发布到 PR 评论
# 3. 运行 Infracost 显示成本变化
#
# 修改建议（用于测试 CI/CD）：
# - 添加/修改标签
# - 更改 versioning 设置
# - 添加新资源

# =============================================================================
# Random ID - 生成唯一后缀
# =============================================================================
# S3 Bucket 名称必须全局唯一
# 使用 random_id 避免命名冲突

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# S3 Bucket - 主资源
# =============================================================================
resource "aws_s3_bucket" "example" {
  bucket = "${var.project_name}-${var.environment}-${random_id.bucket_suffix.hex}"

  # 标签
  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}"
      Description = "CI/CD 示例 Bucket"
    },
    var.additional_tags
  )
}

# =============================================================================
# S3 Bucket Versioning - 版本控制
# =============================================================================
# 版本控制可以防止误删除
# 在 CI/CD 流程中，任何对此设置的修改都会在 PR 中可见

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# =============================================================================
# S3 Bucket Public Access Block - 安全配置
# =============================================================================
# 默认阻止所有公开访问
# 这是 AWS 安全最佳实践

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Bucket Server-Side Encryption - 加密配置
# =============================================================================
# 使用 AWS 管理的密钥 (SSE-S3) 加密
# 存储敏感数据时建议使用 SSE-KMS

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # bucket_key_enabled 仅适用于 aws:kms 加密，AES256 不需要此参数
  }
}
