# =============================================================================
# Provider 配置 - Network Layer (Dev)
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
      ManagedBy   = "Terraform"
      Environment = "dev"
      Layer       = "network"
      Course      = "cloud-atlas-terraform"
    }
  }
}
