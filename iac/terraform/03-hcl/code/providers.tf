# providers.tf
# Provider 配置
#
# 本课程使用 AWS Provider，区域设置为东京（ap-northeast-1）。

terraform {
  # 使用 replace_triggered_by 需要 Terraform 1.2+
  required_version = ">= 1.2.0, < 2.0.0"

  required_providers {
    # Note: AWS Provider 6.x available with breaking changes
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "03-hcl"
    }
  }
}
