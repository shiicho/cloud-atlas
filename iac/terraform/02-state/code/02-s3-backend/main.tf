# main.tf
# 使用远程后端的示例资源
#
# 本文件演示如何配置和使用 S3 远程后端。
# 取消注释 backend 块后，需要运行 terraform init -migrate-state

# -----------------------------------------------------------------------------
# Backend 配置（取消注释以启用）
# -----------------------------------------------------------------------------
#
# 首次使用时：
# 1. 先运行 terraform apply 创建后端基础设施（使用 local state）
# 2. 记录 outputs 中的 bucket_name
# 3. 取消下面其中一个 backend 块的注释并填入 bucket 名称
# 4. 运行 terraform init -migrate-state
#
# S3 后端配置（Terraform 1.10+ 原生锁定）
# terraform {
#   backend "s3" {
#     bucket       = "tfstate-你的后缀"      # 替换为实际值
#     key          = "lesson-02/terraform.tfstate"
#     region       = "ap-northeast-1"
#     encrypt      = true
#     use_lockfile = true                   # 原生 S3 锁定
#   }
# }

# -----------------------------------------------------------------------------
# 示例资源 - 用于演示远程 State
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "demo" {
  bucket = "state-demo-remote-${random_id.suffix.hex}"

  tags = {
    Name        = "State Demo - Remote Backend"
    Environment = "learning"
    Backend     = "s3"
  }
}

# -----------------------------------------------------------------------------
# Time Sleep - 用于锁机制演示
# -----------------------------------------------------------------------------
# 创建一个需要时间的资源，便于在另一个终端尝试并发 apply

resource "time_sleep" "wait" {
  # 设为 0 则不等待；设为 "30s" 可用于锁演示
  create_duration = "0s"

  # 依赖于 demo bucket，确保顺序执行
  depends_on = [aws_s3_bucket.demo]
}

# -----------------------------------------------------------------------------
# State Locking 演示步骤
# -----------------------------------------------------------------------------
#
# 1. 将上面的 create_duration 改为 "30s"
#
# 2. 终端 1 运行：
#    terraform apply -auto-approve
#
# 3. 立即在终端 2 运行：
#    terraform apply -auto-approve
#
# 4. 终端 2 会显示锁定错误：
#    Error: Error acquiring the state lock
#
# 5. 等待终端 1 完成后，终端 2 可以重试
#
# S3 原生锁定能有效防止并发冲突！
# -----------------------------------------------------------------------------
