# =============================================================================
# Backend 配置 - Dev 环境
# =============================================================================
# 每个环境使用独立的 state 路径
# 实际使用时需要先创建 S3 bucket 和 DynamoDB table
# =============================================================================

# 注意：本示例使用 local backend 便于学习
# 实际项目中应使用 S3 backend，如下注释所示

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "dev/terraform.tfstate"  # dev 专用路径
#     region         = "ap-northeast-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

# 学习用：使用 local backend
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
