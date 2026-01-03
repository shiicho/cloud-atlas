# providers.tf
# Terraform State 管理演示
#
# 本课程演示：
# 1. Local State 的问题（默认行为）
# 2. 迁移到 S3 远程后端
# 3. State Locking 机制

terraform {
  required_version = "~> 1.14"

  # -----------------------------------------------------------------------------
  # Backend 配置
  # -----------------------------------------------------------------------------
  # 默认：无 backend 配置 = Local State（terraform.tfstate 在当前目录）
  #
  # Step 3 迁移练习：
  # 1. 取消下面 backend 块的注释
  # 2. 填入你的 bucket 名称（从 CloudFormation 输出获取）
  # 3. 运行 terraform init 触发状态迁移
  #
  # backend "s3" {
  #   bucket       = "tfstate-terraform-course-你的账户ID"  # 替换为实际值
  #   key          = "lesson-02/terraform.tfstate"
  #   region       = "ap-northeast-1"
  #   encrypt      = true
  #   use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
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
    }
  }
}
