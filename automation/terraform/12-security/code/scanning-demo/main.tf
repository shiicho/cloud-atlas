# =============================================================================
# 安全扫描演示（Security Scanning Demo）
# =============================================================================
#
# 使用 Trivy 扫描此目录：
#   trivy config .
#
# 使用 checkov 扫描：
#   checkov -d .
#
# 这个文件包含多种安全问题，用于演示安全扫描工具如何检测它们。
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
}

# =============================================================================
# 问题 1: S3 Bucket 安全配置缺失
# Trivy: AVD-AWS-0089 (versioning), AVD-AWS-0132 (encryption)
# =============================================================================

resource "aws_s3_bucket" "insecure" {
  bucket = "insecure-bucket-demo-${random_id.suffix.hex}"

  # 缺少：版本控制（aws-s3-enable-versioning）
  # 缺少：KMS 加密（aws-s3-encryption-customer-key）
  # 缺少：公开访问阻止

  tags = {
    Name = "insecure-bucket"
  }
}

# 修复后的安全配置
resource "aws_s3_bucket" "secure" {
  bucket = "secure-bucket-demo-${random_id.suffix.hex}"

  tags = {
    Name = "secure-bucket"
  }
}

resource "aws_s3_bucket_versioning" "secure" {
  bucket = aws_s3_bucket.secure.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure" {
  bucket = aws_s3_bucket.secure.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "secure" {
  bucket = aws_s3_bucket.secure.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# 问题 2: Security Group 过于宽松
# Trivy: AVD-AWS-0107 (public ingress)
# =============================================================================

resource "aws_security_group" "insecure" {
  name        = "insecure-sg"
  description = "Insecure security group"

  # ❌ 允许来自任何 IP 的 SSH 访问
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Trivy 会检测到！
    description = "SSH from anywhere - INSECURE"
  }

  # ❌ 允许来自任何 IP 的 RDP 访问
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Trivy 会检测到！
    description = "RDP from anywhere - INSECURE"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "insecure-sg"
  }
}

# ✓ 安全的 Security Group
resource "aws_security_group" "secure" {
  name        = "secure-sg"
  description = "Secure security group"

  # ✓ 只允许公司 VPN IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # 内网 IP
    description = "SSH from internal network only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-sg"
  }
}

# =============================================================================
# 问题 3: IAM 策略过于宽松
# Trivy: AVD-AWS-0057 (no-policy-wildcards)
# =============================================================================

resource "aws_iam_policy" "insecure" {
  name        = "insecure-policy"
  description = "Insecure IAM policy with wildcards"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAll"
        Effect = "Allow"
        Action = "*"      # ❌ 通配符 - 太危险！
        Resource = "*"    # ❌ 所有资源
      }
    ]
  })
}

# ✓ 安全的 IAM 策略
resource "aws_iam_policy" "secure" {
  name        = "secure-policy"
  description = "Secure IAM policy with specific permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.secure.arn,
          "${aws_s3_bucket.secure.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# 问题 4: RDS 公开访问
# Trivy: AVD-AWS-0080 (no-public-db-access)
# =============================================================================

# 注释掉以避免实际创建 RDS（成本高）
# resource "aws_db_instance" "insecure" {
#   identifier = "insecure-db"
#   ...
#   publicly_accessible = true  # ❌ Trivy 会检测到！
# }

# =============================================================================
# 问题 5: CloudWatch Logs 未加密
# Trivy: AVD-AWS-0017 (log-group-customer-key)
# =============================================================================

resource "aws_cloudwatch_log_group" "insecure" {
  name = "/myapp/insecure-logs"
  # 缺少 kms_key_id - Trivy 会建议使用 KMS 加密
}

# ✓ 安全的 Log Group
resource "aws_cloudwatch_log_group" "secure" {
  name       = "/myapp/secure-logs"
  kms_key_id = aws_kms_key.logs.arn  # ✓ KMS 加密
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs"
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
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

# =============================================================================
# 数据源
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# 忽略特定检查（在某些情况下是合理的）
# =============================================================================

# 有时候你知道某个检查不适用，可以使用注释忽略
resource "aws_s3_bucket" "logs" {
  # trivy:ignore:AVD-AWS-0089 - 日志桶不需要版本控制，有生命周期策略
  bucket = "logs-bucket-${random_id.suffix.hex}"

  tags = {
    Name = "logs-bucket"
  }
}
