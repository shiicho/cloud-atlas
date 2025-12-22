# =============================================================================
# 監査ログ基盤 - S3 + CloudTrail 構成
# =============================================================================
#
# 日本 IT 企業の監査要件（ISMS/ISMAP/SOC2）に対応するため、
# Terraform State のログ記録・変更履歴・アクセス追跡を設定します。
#
# このコードで作成されるもの：
# 1. State 保存用 S3 バケット（Versioning + 暗号化）
# 2. ログ保存用 S3 バケット
# 3. CloudTrail（API 呼び出し記録）
# 4. KMS キー（State 暗号化）
#
# Note: Terraform 1.10+ は S3 原生锁定（use_lockfile = true）を使用
#
# =============================================================================

# -----------------------------------------------------------------------------
# ランダム ID 生成（バケット名をユニークにするため）
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# 現在のアカウント情報を取得
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# State 保存用 S3 バケット
# 監査要件: 変更履歴の保持、暗号化、アクセス記録
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project}-tfstate-${random_id.suffix.hex}"

  # 削除防止（本番環境では true を推奨）
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name    = "${var.project}-tfstate"
    Purpose = "terraform-state"
  })
}

# Versioning 有効化（変更履歴保持 - 監査必須）
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS キー（State 暗号化用）
resource "aws_kms_key" "tfstate" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM policies"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-tfstate-kms"
  })
}

resource "aws_kms_alias" "tfstate" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.tfstate.key_id
}

# S3 サーバー側暗号化（KMS 使用）
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.tfstate.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# パブリックアクセスブロック（監査要件：不正アクセス防止）
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ライフサイクルルール（古いバージョンの自動削除）
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    # 非現行バージョンを指定日数後に削除
    noncurrent_version_expiration {
      noncurrent_days = var.state_version_retention_days
    }

    # マルチパートアップロードの未完了分を削除
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# ログ保存用 S3 バケット
# State へのアクセスログと CloudTrail ログを保存
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project}-tfstate-logs-${random_id.suffix.hex}"

  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name    = "${var.project}-tfstate-logs"
    Purpose = "audit-logs"
  })
}

# ログバケットの暗号化
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ログバケットのパブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ログバケットのライフサイクル（ISMAP 対応: 長期保持 + Glacier 移行）
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"

    # 90日後に Glacier に移行（ISMAP 要件）
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # 指定期間後に削除
    expiration {
      days = var.log_retention_days
    }
  }
}

# S3 Access Logging（State バケットへのアクセスを記録）
resource "aws_s3_bucket_logging" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "access-logs/"
}

# ログバケットのバケットポリシー（CloudTrail からの書き込み許可）
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-terraform-audit"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/cloudtrail/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-terraform-audit"
          }
        }
      },
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/access-logs/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.tfstate.arn
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudTrail（API 呼び出し記録）
# terraform apply 時の全 AWS API 呼び出しを記録
# -----------------------------------------------------------------------------
resource "aws_cloudtrail" "terraform" {
  name                          = "${var.project}-terraform-audit"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = var.multi_region_trail
  enable_log_file_validation    = true # ログ改竄検知

  # S3 のデータイベントも記録（State アクセス追跡）
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.tfstate.arn}/"]
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project}-terraform-audit"
  })

  depends_on = [aws_s3_bucket_policy.logs]
}

# -----------------------------------------------------------------------------
# State Locking - S3 原生锁定
# Terraform 1.10+ 使用 use_lockfile = true
# -----------------------------------------------------------------------------
# .tflock ファイルで锁机制を実現します。
# backend "s3" で use_lockfile = true を設定することで、
# S3 上に .tflock ファイルが作成され、ロック機能が実現されます。
#
# 使用方式：
#   backend "s3" {
#     bucket       = "..."
#     key          = "..."
#     region       = "..."
#     encrypt      = true
#     use_lockfile = true  # S3 原生锁定
#   }
# -----------------------------------------------------------------------------
