# providers.tf
# Provider 配置 - Local State 演示
#
# 本配置使用 Local State（默认行为）。
# 这是一个反模式演示，展示为什么团队协作不应使用 Local State。

terraform {
  required_version = ">= 1.0.0"

  # 注意：没有 backend 配置
  # Terraform 默认使用 Local State（当前目录的 terraform.tfstate）

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
      Project   = "terraform-course"
      ManagedBy = "terraform"
      Lesson    = "02-state"
      Demo      = "local-state-antipattern"
    }
  }
}
