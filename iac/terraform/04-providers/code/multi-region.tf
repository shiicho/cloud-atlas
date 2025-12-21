# multi-region.tf
# 多区域 Provider 配置演示
#
# 使用 Provider alias 在多个区域部署资源。
# 常见场景：
# - 灾难恢复（DR）
# - 低延迟全球部署
# - 数据合规（数据必须存储在特定区域）

# -----------------------------------------------------------------------------
# Alias Provider - 大阪区域
# -----------------------------------------------------------------------------
# 默认 Provider 已在 providers.tf 中配置（东京）
# 这里添加一个 alias Provider 用于大阪区域

provider "aws" {
  alias  = "osaka"
  region = "ap-northeast-3"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "04-providers"
      Region    = "osaka"
    }
  }
}

# -----------------------------------------------------------------------------
# 使用 Alias Provider 创建资源
# -----------------------------------------------------------------------------
# 使用 provider 参数指定使用哪个 Provider
#
# 语法：
#   provider = aws.alias_name
#
# 如果不指定，使用默认 Provider（无 alias 的那个）

resource "aws_s3_bucket" "osaka" {
  provider = aws.osaka

  bucket = "provider-demo-osaka-${random_id.suffix.hex}"

  tags = {
    Name        = "Multi-Region Demo - Osaka"
    Environment = "learning"
  }
}

# -----------------------------------------------------------------------------
# 多 Provider 应用场景
# -----------------------------------------------------------------------------
#
# 场景 1: 多区域灾备
# ──────────────────
# provider "aws" {
#   region = "ap-northeast-1"  # 主区域
# }
# provider "aws" {
#   alias  = "dr"
#   region = "ap-northeast-3"  # DR 区域
# }
#
# 场景 2: 多账户管理
# ──────────────────
# provider "aws" {
#   region = "ap-northeast-1"
# }
# provider "aws" {
#   alias   = "prod"
#   region  = "ap-northeast-1"
#   assume_role {
#     role_arn = "arn:aws:iam::PROD_ACCOUNT:role/TerraformRole"
#   }
# }
#
# 场景 3: 混合云
# ──────────────
# provider "aws" { ... }
# provider "azurerm" { ... }
# provider "google" { ... }
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Data Source 使用 alias Provider
# -----------------------------------------------------------------------------
# Data Source 也可以指定 Provider

data "aws_region" "osaka" {
  provider = aws.osaka
}

# -----------------------------------------------------------------------------
# Module 中传递 Provider
# -----------------------------------------------------------------------------
# 当模块需要使用非默认 Provider 时：
#
# module "dr_vpc" {
#   source = "./modules/vpc"
#
#   providers = {
#     aws = aws.osaka
#   }
# }
# -----------------------------------------------------------------------------
