# =============================================================================
# providers.tf - Provider 配置
# =============================================================================
#
# 代码生成示例 - 展示如何批量导入多个资源
# 使用 terraform plan -generate-config-out=generated.tf 自动生成代码
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
  region = "ap-northeast-1"

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Course    = "cloud-atlas-terraform"
      Lesson    = "09-import"
    }
  }
}
