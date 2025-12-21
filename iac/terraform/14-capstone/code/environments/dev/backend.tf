# =============================================================================
# environments/dev/backend.tf
# 远程后端配置
# =============================================================================
#
# 使用前，请先创建 S3 Bucket 和 DynamoDB Table：
#
# 1. 创建 S3 Bucket（替换 YOUR_ACCOUNT_ID）：
#    aws s3 mb s3://tfstate-capstone-YOUR_ACCOUNT_ID --region ap-northeast-1
#
# 2. 启用版本控制：
#    aws s3api put-bucket-versioning \
#      --bucket tfstate-capstone-YOUR_ACCOUNT_ID \
#      --versioning-configuration Status=Enabled
#
# 3. 创建 DynamoDB 锁表：
#    aws dynamodb create-table \
#      --table-name tfstate-lock-capstone \
#      --attribute-definitions AttributeName=LockID,AttributeType=S \
#      --key-schema AttributeName=LockID,KeyType=HASH \
#      --billing-mode PAY_PER_REQUEST \
#      --region ap-northeast-1
#
# 4. 更新下面的 bucket 名称后取消注释
#
# =============================================================================

# 取消注释以启用远程后端
# terraform {
#   backend "s3" {
#     bucket         = "tfstate-capstone-YOUR_ACCOUNT_ID"  # 替换为你的 Bucket 名称
#     key            = "dev/terraform.tfstate"
#     region         = "ap-northeast-1"
#     dynamodb_table = "tfstate-lock-capstone"
#     encrypt        = true
#   }
# }
