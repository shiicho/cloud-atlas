# providers.tf
# Provider 配置
# =============================================================================

terraform {
  # moved blocks 需要 Terraform 1.1+
  required_version = ">= 1.1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "10-drift-moved"
    }
  }
}
