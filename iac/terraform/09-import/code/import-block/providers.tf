# =============================================================================
# providers.tf - Provider 配置
# =============================================================================
#
# Import Block 示例 - Terraform 1.5+ 推荐方式
# 这是声明式导入，比传统 terraform import 命令更适合团队协作和 CI/CD
#
# =============================================================================

terraform {
  # 最低版本要求 - Import blocks 需要 1.5+
  # 推荐使用最新版本以获得最佳的代码生成支持
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # 5.x 版本，推荐使用最新
    }
  }
}

# AWS Provider 配置
# 区域设置为东京（ap-northeast-1）
provider "aws" {
  region = "ap-northeast-1"

  # 默认标签 - 所有资源都会添加这些标签
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Course    = "cloud-atlas-terraform"
      Lesson    = "09-import"
    }
  }
}
