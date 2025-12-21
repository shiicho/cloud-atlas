# providers.tf
# Provider 配置
#
# 本文件配置 Terraform 和 AWS Provider 的版本约束。
# 使用 S3 远程后端存储状态文件。

# =============================================================================
# Terraform 配置
# =============================================================================
terraform {
  # Terraform 版本约束
  required_version = ">= 1.5.0"

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

  # 远程后端配置
  # 在 CI/CD 环境中使用 S3 存储状态
  # 注意：需要先创建 S3 bucket 和 DynamoDB 表
  #
  # 参考 Lesson 02: 状态管理与远程后端
  # backend "s3" {
  #   bucket         = "terraform-state-YOUR_ACCOUNT_ID"
  #   key            = "cicd-example/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
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
