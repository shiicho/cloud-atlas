# =============================================================================
# Provider 配置
# =============================================================================
# 本文件定义 Terraform 和 Provider 的版本要求
# 所有 workspace 共享同一份 provider 配置
# =============================================================================

terraform {
  required_version = "~> 1.14"

  # Provider 版本要求
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # 5.x 版本，不超过 6.0
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# AWS Provider 配置
# 所有 workspace 使用同一个 region
provider "aws" {
  region = "ap-northeast-1"  # 东京区域

  # 默认标签（会自动添加到所有资源）
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Course    = "cloud-atlas-terraform"
      Lesson    = "08-layout"
    }
  }
}
