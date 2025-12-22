# =============================================================================
# Provider Configuration
# =============================================================================
#
# Terraform and provider version constraints for the sample module.
#
# =============================================================================

terraform {
  required_version = "~> 1.14"

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
      ManagedBy = "Terraform"
      Course    = "cloud-atlas"
      Lesson    = "13-testing"
    }
  }
}
