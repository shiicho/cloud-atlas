# =============================================================================
# import.tf - Import Block 定义
# =============================================================================
#
# Import Block 是 Terraform 1.5+ 引入的声明式导入方式
#
# 优势:
#   1. 代码即文档 - 导入意图被记录在代码中
#   2. 可重复执行 - 多次 apply 不会报错
#   3. CI/CD 友好 - 无需在 pipeline 中执行特殊命令
#   4. 代码生成 - 可配合 -generate-config-out 自动生成资源代码
#
# 使用方法:
#   1. 将下面的 id 替换为你要导入的 EC2 Instance ID
#   2. 运行 terraform init
#   3. 运行 terraform plan -generate-config-out=generated.tf
#   4. 审查生成的代码，移动到 main.tf
#   5. 运行 terraform apply 完成导入
#
# =============================================================================

# -----------------------------------------------------------------------------
# EC2 实例导入
# -----------------------------------------------------------------------------
# 导入手动创建的 EC2 实例到 Terraform 管理
#
# 步骤:
#   1. 从 setup-existing-resources.sh 输出或 AWS Console 获取 Instance ID
#   2. 替换下面的 id 值
#   3. 执行 terraform plan -generate-config-out=generated.tf

import {
  # AWS 资源的唯一标识符
  # 格式因资源类型而异，EC2 实例使用 Instance ID
  id = "i-0abc123def456789"  # <-- 替换为你的 Instance ID

  # 导入目标 - Terraform 资源地址
  # 格式: <资源类型>.<资源名称>
  to = aws_instance.imported_legacy
}

# -----------------------------------------------------------------------------
# 其他常见资源的 Import ID 格式示例（供参考）
# -----------------------------------------------------------------------------
#
# # S3 Bucket - 使用 bucket 名称
# import {
#   id = "my-bucket-name"
#   to = aws_s3_bucket.example
# }
#
# # Security Group - 使用 SG ID
# import {
#   id = "sg-0123456789abcdef0"
#   to = aws_security_group.example
# }
#
# # VPC - 使用 VPC ID
# import {
#   id = "vpc-0123456789abcdef0"
#   to = aws_vpc.example
# }
#
# # Subnet - 使用 Subnet ID
# import {
#   id = "subnet-0123456789abcdef0"
#   to = aws_subnet.example
# }
#
# # IAM Role - 使用 Role 名称
# import {
#   id = "my-role-name"
#   to = aws_iam_role.example
# }
#
# # RDS Instance - 使用 DB Instance Identifier
# import {
#   id = "my-database"
#   to = aws_db_instance.example
# }
#
# # ALB - 使用 ARN
# import {
#   id = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/my-alb/1234567890abcdef"
#   to = aws_lb.example
# }
