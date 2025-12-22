# providers.tf
# Provider 配置
#
# 本文件配置 Terraform 和 AWS Provider 的版本约束。
# 使用 S3 远程后端存储状态文件。

# =============================================================================
# Terraform 配置
# =============================================================================
terraform {
  required_version = "~> 1.14"

  # Provider 版本约束
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # 5.x 版本
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # 远程后端配置见 backend.tf
  # 参考 Lesson 02: 状态管理与远程后端
}

# =============================================================================
# AWS Provider
# =============================================================================
provider "aws" {
  region = var.aws_region

  # 默认标签：自动添加到所有资源
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "cicd-example"
      Environment = var.environment
      Repository  = "cloud-atlas"
    }
  }
}
