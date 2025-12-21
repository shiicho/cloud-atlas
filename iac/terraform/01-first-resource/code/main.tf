# main.tf
# 第一个 Terraform 资源：S3 Bucket
#
# 本文件演示 Terraform 资源定义的基本语法。
# 创建一个启用版本控制的 S3 Bucket。

# -----------------------------------------------------------------------------
# Random ID - 生成随机后缀
# -----------------------------------------------------------------------------
# S3 Bucket 名称必须全球唯一。
# 使用 random_id 生成随机后缀，避免命名冲突。

resource "random_id" "bucket_suffix" {
  byte_length = 4    # 生成 4 字节（8 个十六进制字符）
}

# -----------------------------------------------------------------------------
# S3 Bucket - 主资源
# -----------------------------------------------------------------------------
# resource "资源类型" "资源名称" { ... }
#
# 资源类型: aws_s3_bucket（AWS Provider 定义）
# 资源名称: first_bucket（你定义的本地名称，用于引用）

resource "aws_s3_bucket" "first_bucket" {
  # bucket 参数：S3 桶名
  # 使用字符串插值 ${...} 组合前缀和随机后缀
  bucket = "my-first-terraform-bucket-${random_id.bucket_suffix.hex}"

  # tags 参数：资源标签
  # 除了 default_tags，还可以添加资源特定的标签
  tags = {
    Name        = "My First Terraform Bucket"
    Environment = "learning"
    Purpose     = "Terraform 课程练习"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Versioning - 版本控制配置
# -----------------------------------------------------------------------------
# 从 AWS Provider 4.0 开始，S3 Bucket 的附加配置
# 需要使用独立的资源块（而不是 bucket 资源的嵌套块）。
#
# 这是 AWS Provider 的 "资源分离" 设计模式。

resource "aws_s3_bucket_versioning" "first_bucket" {
  # 引用其他资源的属性
  # 语法: 资源类型.资源名称.属性
  bucket = aws_s3_bucket.first_bucket.id

  versioning_configuration {
    status = "Enabled"    # 启用版本控制
  }
}

# -----------------------------------------------------------------------------
# 资源依赖关系
# -----------------------------------------------------------------------------
#
# Terraform 自动分析资源引用，建立隐式依赖：
#
#   random_id.bucket_suffix
#          │
#          ▼ (bucket 名称引用 random_id.hex)
#   aws_s3_bucket.first_bucket
#          │
#          ▼ (bucket 参数引用 aws_s3_bucket.id)
#   aws_s3_bucket_versioning.first_bucket
#
# 执行顺序由依赖关系自动决定，无需手动指定。
# -----------------------------------------------------------------------------
