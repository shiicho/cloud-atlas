# =============================================================================
# Variables - 変更管理用 IAM Role の入力変数
# =============================================================================
#
# 本ファイルは Plan Role と Apply Role の作成に必要な変数を定義します。
# 環境に応じて terraform.tfvars で値を上書きしてください。
#
# =============================================================================

# -----------------------------------------------------------------------------
# GitHub 設定
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub Organization または Username"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.github_org))
    error_message = "GitHub org/username は英数字とハイフンのみ使用可能です"
  }
}

variable "github_repo" {
  description = "GitHub Repository 名（org/repo の repo 部分）"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.github_repo))
    error_message = "Repository 名は英数字、ドット、アンダースコア、ハイフンのみ使用可能です"
  }
}

# -----------------------------------------------------------------------------
# Terraform State 設定
# -----------------------------------------------------------------------------

variable "state_bucket" {
  description = "Terraform State を保存する S3 バケット名"
  type        = string
}

variable "lock_table" {
  description = "Terraform State Lock 用の DynamoDB テーブル名"
  type        = string
  default     = "terraform-locks"
}

# -----------------------------------------------------------------------------
# プロジェクト設定
# -----------------------------------------------------------------------------

variable "project_prefix" {
  description = "プロジェクトのプレフィックス（リソース名に使用）"
  type        = string
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_prefix))
    error_message = "Project prefix は小文字英数字とハイフンのみ使用可能です"
  }
}

variable "environment" {
  description = "環境名（dev, staging, prod）"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment は dev, staging, prod のいずれかです"
  }
}

# -----------------------------------------------------------------------------
# AWS 設定
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# -----------------------------------------------------------------------------
# タグ設定
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "全リソースに付与する共通タグ"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Course    = "cloud-atlas"
  }
}
