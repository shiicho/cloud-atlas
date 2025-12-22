# =============================================================================
# Provider 配置 - Foundations Layer (Dev)
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
      Layer       = "foundations"
      Course      = "cloud-atlas-terraform"
    }
  }
}
