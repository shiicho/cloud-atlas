# =============================================================================
# import.tf - 批量 Import 示例
# =============================================================================
#
# 本示例展示如何同时导入多个相关资源
# 适用于导入一组关联的基础设施（如 EC2 + SG + Subnet）
#
# 使用方法:
#   1. 替换所有 id 为实际的资源 ID
#   2. terraform init
#   3. terraform plan -generate-config-out=generated.tf
#   4. 审查并优化 generated.tf
#   5. terraform apply
#
# =============================================================================

# -----------------------------------------------------------------------------
# EC2 实例
# -----------------------------------------------------------------------------
import {
  # EC2 Instance ID
  # 格式: i-xxxxxxxxxxxxxxxxx
  id = "i-0abc123def456789"  # TODO: 替换

  to = aws_instance.web_server
}

# -----------------------------------------------------------------------------
# 安全组
# -----------------------------------------------------------------------------
import {
  # Security Group ID
  # 格式: sg-xxxxxxxxxxxxxxxxx
  id = "sg-0123456789abcdef0"  # TODO: 替换

  to = aws_security_group.web_sg
}

# -----------------------------------------------------------------------------
# 子网（如果需要导入）
# -----------------------------------------------------------------------------
# 注意：共享的 VPC/Subnet 通常使用 data source 引用，而不是导入
# 仅当需要 Terraform 管理子网时才导入

# import {
#   # Subnet ID
#   # 格式: subnet-xxxxxxxxxxxxxxxxx
#   id = "subnet-0fedcba9876543210"
#
#   to = aws_subnet.main
# }

# -----------------------------------------------------------------------------
# VPC（如果需要导入）
# -----------------------------------------------------------------------------
# 通常 VPC 由平台团队管理，应用团队使用 data source 引用

# import {
#   # VPC ID
#   # 格式: vpc-xxxxxxxxxxxxxxxxx
#   id = "vpc-0123456789abcdef0"
#
#   to = aws_vpc.main
# }

# -----------------------------------------------------------------------------
# 其他常见资源示例
# -----------------------------------------------------------------------------

# # S3 Bucket
# import {
#   id = "my-bucket-name"
#   to = aws_s3_bucket.data
# }

# # IAM Role
# import {
#   id = "my-app-role"
#   to = aws_iam_role.app
# }

# # IAM Policy (使用 ARN)
# import {
#   id = "arn:aws:iam::123456789012:policy/my-policy"
#   to = aws_iam_policy.app
# }

# # RDS Instance
# import {
#   id = "my-database"
#   to = aws_db_instance.main
# }

# # EBS Volume
# import {
#   id = "vol-0123456789abcdef0"
#   to = aws_ebs_volume.data
# }

# # Elastic IP
# import {
#   id = "eipalloc-0123456789abcdef0"
#   to = aws_eip.web
# }
