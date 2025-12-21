# =============================================================================
# 変数定義 - 監査ログ基盤
# =============================================================================

variable "project" {
  description = "プロジェクト名（リソース名のプレフィックスに使用）"
  type        = string
  default     = "myproject"
}

variable "tags" {
  description = "全リソースに付与する共通タグ"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "audit-compliance"
  }
}

variable "force_destroy" {
  description = "S3 バケットを強制削除するか（本番では false 推奨）"
  type        = bool
  default     = false
}

variable "state_version_retention_days" {
  description = "State バージョンの保持日数（監査要件に応じて設定）"
  type        = number
  default     = 365 # 1年間

  validation {
    condition     = var.state_version_retention_days >= 90
    error_message = "ISMS/ISMAP 要件: State バージョンは最低 90 日間保持する必要があります。"
  }
}

variable "log_retention_days" {
  description = "ログの保持日数（ISMAP では最低 90 日、SOC2 では 1 年推奨）"
  type        = number
  default     = 2555 # 約 7 年（一部業界の要件）

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "ISMAP 要件: ログは最低 90 日間保持する必要があります。"
  }
}

variable "multi_region_trail" {
  description = "CloudTrail をマルチリージョンで有効化するか"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# 環境別設定例
# -----------------------------------------------------------------------------
#
# 開発環境（dev.tfvars）:
#   state_version_retention_days = 90
#   log_retention_days           = 90
#   force_destroy                = true
#   multi_region_trail           = false
#
# 本番環境（prod.tfvars）:
#   state_version_retention_days = 365
#   log_retention_days           = 2555
#   force_destroy                = false
#   multi_region_trail           = true
#
# -----------------------------------------------------------------------------
