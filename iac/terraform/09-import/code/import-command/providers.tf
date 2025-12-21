# =============================================================================
# providers.tf - Provider 配置
# =============================================================================
#
# 传统 terraform import 命令示例
# 这是 Terraform 1.5 之前的标准导入方式
#
# 注意：推荐使用 Import Block (../import-block/) 方式
# 此目录仅用于了解传统方式，以便维护旧项目
#
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

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
      ManagedBy = "Terraform"
      Course    = "cloud-atlas-terraform"
      Lesson    = "09-import"
    }
  }
}
