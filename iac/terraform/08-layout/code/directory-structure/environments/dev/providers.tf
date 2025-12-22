# =============================================================================
# Provider 配置 - Dev 环境
# =============================================================================

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = "dev"
      Course      = "cloud-atlas-terraform"
      Lesson      = "08-layout"
    }
  }
}
