# =============================================================================
# 主资源定义 - Workspaces 示例
# =============================================================================
# 本示例演示 Terraform Workspaces 的使用方法
# 同一份代码，通过 workspace 切换来管理不同环境
#
# 关键点：
# 1. terraform.workspace 变量自动获取当前 workspace 名称
# 2. 可以用 lookup() 或 map 来实现环境差异化配置
# 3. 所有 workspace 共享同一份代码，只是 state 分离
# =============================================================================

# -----------------------------------------------------------------------------
# 本地变量
# -----------------------------------------------------------------------------
locals {
  # 当前环境名称
  environment = terraform.workspace

  # 获取当前环境的配置
  # 如果 workspace 不在 map 中，使用 default 配置
  env_config = lookup(
    var.environment_configs,
    terraform.workspace,
    var.environment_configs["default"]
  )

  # 通用标签
  common_tags = {
    Environment = local.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workspace   = terraform.workspace
  }
}

# -----------------------------------------------------------------------------
# 随机后缀（保证 bucket 名称全局唯一）
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------
# 使用 workspace 名称作为 bucket 名称的一部分
# 这样每个 workspace 创建独立的 bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "demo" {
  # bucket 名称包含 workspace 名称，保证不同环境不冲突
  bucket = "${var.bucket_prefix}-${local.environment}-${random_id.suffix.hex}"

  # 强制销毁（即使有对象也能删除）
  # 注意：生产环境不建议开启
  force_destroy = local.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${var.bucket_prefix}-${local.environment}"
  })
}

# -----------------------------------------------------------------------------
# S3 Bucket 版本控制
# -----------------------------------------------------------------------------
# 根据环境配置决定是否开启版本控制
# prod 和 staging 开启，dev 不开启
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    # 根据环境配置决定是否启用
    status = local.env_config.enable_versioning ? "Enabled" : "Suspended"
  }
}

# -----------------------------------------------------------------------------
# S3 生命周期规则
# -----------------------------------------------------------------------------
# 不同环境使用不同的过期天数
# 这是 workspaces 模式下实现差异化配置的方式
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    id     = "cleanup-old-objects"
    status = "Enabled"

    # 对象过期天数根据环境不同
    expiration {
      days = local.env_config.lifecycle_days
    }

    # 非当前版本对象 7 天后删除（仅版本控制开启时有效）
    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    # 多部分上传超时清理
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# -----------------------------------------------------------------------------
# S3 服务端加密
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    # bucket_key_enabled 仅适用于 aws:kms 加密，AES256 不需要此参数
  }
}

# -----------------------------------------------------------------------------
# S3 公共访问阻止
# -----------------------------------------------------------------------------
# 安全最佳实践：阻止所有公共访问
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
