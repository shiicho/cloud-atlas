# providers.tf
# Provider 配置 - S3 Remote Backend 演示
#
# 本配置演示生产级 Terraform 后端设置。

terraform {
  # 使用 S3 native locking 需要 Terraform 1.10+
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    # Note: AWS Provider 6.x available with breaking changes
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "02-state"
    }
  }
}
