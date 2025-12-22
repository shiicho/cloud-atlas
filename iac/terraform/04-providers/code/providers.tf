# providers.tf
# Provider 配置与版本管理
#
# 本文件演示：
# 1. required_version - Terraform CLI 版本约束
# 2. required_providers - Provider 版本约束
# 3. 版本约束语法详解

terraform {
  # -------------------------------------------------------------------------
  # Terraform CLI 版本约束
  # -------------------------------------------------------------------------
  # 确保团队使用兼容的 Terraform 版本
  #
  # 语法：
  #   = 1.5.0      精确版本
  #   >= 1.5.0     最低版本
  #   ~> 1.5.0     1.5.x（不超过 1.6）
  #   >= 1.5, < 2  范围约束
  required_version = "~> 1.14"

  # -------------------------------------------------------------------------
  # Provider 版本约束
  # -------------------------------------------------------------------------
  required_providers {
    # AWS Provider
    # Note: AWS Provider 6.x available (June 2025) with breaking changes
    # See: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade
    aws = {
      # source: Provider 来源
      # 格式: namespace/name（如 hashicorp/aws）
      # 完整格式: registry.terraform.io/hashicorp/aws
      source = "hashicorp/aws"

      # version: 版本约束
      #
      # 推荐使用 ~> (悲观约束):
      # - 允许 patch 更新（安全修复）
      # - 阻止 minor/major 的 breaking changes
      #
      # ~> 5.0 允许 5.x，不超过 6.0
      version = "~> 5.0"
    }

    # Random Provider（生成随机值）
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 默认 AWS Provider 配置
# -----------------------------------------------------------------------------
provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "04-providers"
    }
  }
}

# -----------------------------------------------------------------------------
# 版本约束语法参考
# -----------------------------------------------------------------------------
#
# | 语法         | 含义               | 匹配示例                |
# |--------------|--------------------|-------------------------|
# | = 5.0.0      | 精确版本           | 5.0.0                   |
# | != 5.0.0     | 排除版本           | 任意非 5.0.0            |
# | > 5.0        | 大于               | 5.0.1, 5.1.0, 6.0.0     |
# | >= 5.0       | 大于等于           | 5.0.0, 5.0.1, 6.0.0     |
# | < 6.0        | 小于               | 5.x.x                   |
# | <= 5.0       | 小于等于           | 5.0.0, 4.x.x            |
# | ~> 5.0       | >= 5.0, < 6.0      | 5.0.0, 5.99.99          |
# | ~> 5.0.0     | >= 5.0.0, < 5.1    | 5.0.0, 5.0.99           |
#
# 组合约束（用逗号分隔）：
#   >= 5.0, < 6.0, != 5.5.0
# -----------------------------------------------------------------------------
