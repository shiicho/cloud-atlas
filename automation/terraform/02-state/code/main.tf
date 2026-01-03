# main.tf
# Terraform State 管理演示
#
# 本课程流程：
# 1. 使用 Local State 创建资源，体验问题
# 2. 配置 S3 远程后端，迁移 State
# 3. 体验 State Locking 机制

# -----------------------------------------------------------------------------
# Random ID - 生成唯一后缀
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket - 演示资源
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "demo" {
  bucket = "state-demo-${random_id.suffix.hex}"

  tags = {
    Name        = "State Demo Bucket"
    Environment = "learning"
  }
}

# -----------------------------------------------------------------------------
# Time Sleep - 用于 State Locking 演示
# -----------------------------------------------------------------------------
# Step 5 锁机制演示：
# 1. 将 create_duration 改为 "30s"
# 2. 终端 1 运行：terraform apply -auto-approve
# 3. 立即在终端 2 运行：terraform apply -auto-approve
# 4. 终端 2 会显示锁定错误：Error acquiring the state lock
# 5. 等待终端 1 完成后，终端 2 可以重试
#
# 演示完成后记得改回 "0s"

resource "time_sleep" "wait" {
  create_duration = "0s"  # 改为 "30s" 进行锁演示

  depends_on = [aws_s3_bucket.demo]
}
