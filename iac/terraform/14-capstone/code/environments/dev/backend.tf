# =============================================================================
# environments/dev/backend.tf
# 远程后端配置
# =============================================================================
#
# 使用前，请先创建 S3 Bucket：
#
# 1. 创建 S3 Bucket（替换 YOUR_ACCOUNT_ID）：
#    aws s3 mb s3://tfstate-capstone-YOUR_ACCOUNT_ID --region ap-northeast-1
#
# 2. 启用版本控制：
#    aws s3api put-bucket-versioning \
#      --bucket tfstate-capstone-YOUR_ACCOUNT_ID \
#      --versioning-configuration Status=Enabled
#
# 3. 更新下面的 bucket 名称后取消注释
#
# =============================================================================

# 取消注释以启用远程后端
# terraform {
#   backend "s3" {
#     bucket       = "tfstate-capstone-YOUR_ACCOUNT_ID"  # 替换为你的 Bucket 名称
#     key          = "dev/terraform.tfstate"
#     region       = "ap-northeast-1"
#     use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
#     encrypt      = true
#   }
# }
