# main.tf
# 基本资源演示
#
# 创建一个 S3 Bucket 用于演示 Provider 功能。

# -----------------------------------------------------------------------------
# Random ID - 确保资源名称唯一
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket - 使用默认 Provider（东京）
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "demo" {
  bucket = "provider-demo-${random_id.suffix.hex}"

  tags = {
    Name        = "Provider Demo Bucket"
    Environment = "learning"
  }
}

# -----------------------------------------------------------------------------
# Provider 版本信息
# -----------------------------------------------------------------------------
#
# 运行以下命令查看 Provider 信息：
#
# terraform version -json
#   → 显示 Terraform 和 Provider 版本
#
# terraform providers
#   → 显示配置中引用的 Provider
#
# terraform init -upgrade
#   → 升级到约束范围内的最新版本
#
# terraform providers lock -platform=linux_amd64
#   → 为特定平台生成 hash（跨平台团队）
# -----------------------------------------------------------------------------
