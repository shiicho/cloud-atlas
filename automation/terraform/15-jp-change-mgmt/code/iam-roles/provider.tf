# =============================================================================
# Provider Configuration - AWS Provider 設定
# =============================================================================
#
# 変更管理用 IAM Role を作成するための Provider 設定です。
#
# =============================================================================

terraform {
  required_version = "~> 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# 現在の AWS アカウント情報を取得
data "aws_caller_identity" "current" {}

# 現在のリージョン情報を取得
data "aws_region" "current" {}
