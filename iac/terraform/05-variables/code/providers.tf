# providers.tf
# Provider 配置

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

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
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Lesson    = "05-variables"
    }
  }
}
