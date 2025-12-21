# =============================================================================
# Backend 配置 - Application Layer (Dev)
# =============================================================================

# 学习用：local backend
# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state"
#     key            = "dev/application/terraform.tfstate"
#     region         = "ap-northeast-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
