# providers.tf
# Provider 配置
# =============================================================================
#
# 本文件配置 Terraform 和 AWS Provider 的版本约束。
# 使用东京区域 (ap-northeast-1)，适合日本 IT 现场的学习场景。

terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS Provider 配置
provider "aws" {
  region = "ap-northeast-1"  # 东京区域

  # 默认标签 - 所有资源自动添加
  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "10-drift"
    }
  }
}
