# providers.tf
# Provider 配置
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
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "10-drift-moved"
    }
  }
}
