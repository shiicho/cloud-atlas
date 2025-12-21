# providers.tf
# 定义使用的 Provider 及其版本
#
# 本文件配置 Terraform 和 AWS Provider 的版本约束。
# 团队协作时，确保所有成员使用兼容的版本。

terraform {
  # Terraform CLI 版本约束
  # 使用 1.0.0 或更高版本
  required_version = ">= 1.0.0"

  # Provider 版本约束
  required_providers {
    # AWS Provider
    aws = {
      source  = "hashicorp/aws"    # Provider 来源（Terraform Registry）
      version = "~> 5.0"           # 悲观约束：5.x（不超过 6.0）
    }

    # Random Provider（生成随机值）
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# AWS Provider 配置
provider "aws" {
  # 区域设置
  # ap-northeast-1 = 东京（日本用户推荐）
  region = "ap-northeast-1"

  # 默认标签
  # 所有通过此 Provider 创建的资源都会自动添加这些标签
  # 便于成本追踪和资源管理
  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "01-first-resource"
    }
  }
}

# -----------------------------------------------------------------------------
# 版本约束语法说明
# -----------------------------------------------------------------------------
#
# = 5.0.0     精确版本，只使用 5.0.0
# >= 5.0      最低版本，5.0 或更高
# ~> 5.0      悲观约束，允许 5.x（不超过 6.0）
# >= 5.0, < 6.0  范围约束，5.0 到 5.x
#
# 推荐使用 ~> 语法：
# - 允许自动获取 patch 更新（安全修复）
# - 阻止 major 版本的 breaking changes
# -----------------------------------------------------------------------------
