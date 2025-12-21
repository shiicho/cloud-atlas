# =============================================================================
# S3 Bucket Module - Main Configuration
# =============================================================================
#
# This module creates an S3 bucket with:
# - Random suffix for unique naming
# - Configurable versioning
# - Optional access logging
# - Environment-based tagging
#
# Used as example for terraform test demonstrations.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Random Suffix for Unique Bucket Names
# -----------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# Main S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "main" {
  bucket        = "${var.bucket_prefix}${random_id.bucket_suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(
    {
      Name        = "${var.bucket_prefix}${random_id.bucket_suffix.hex}"
      Environment = var.environment
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Bucket Versioning
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# Public Access Block (Security Best Practice)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Server-Side Encryption (Security Best Practice)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# Access Logging (Optional, Recommended for Production)
# -----------------------------------------------------------------------------

# Logging target bucket (created only when logging is enabled)
resource "aws_s3_bucket" "logs" {
  count = var.enable_logging ? 1 : 0

  bucket        = "${var.bucket_prefix}logs-${random_id.bucket_suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(
    {
      Name        = "${var.bucket_prefix}logs-${random_id.bucket_suffix.hex}"
      Environment = var.environment
      Purpose     = "Access Logs"
    },
    var.tags
  )
}

# Logging configuration
resource "aws_s3_bucket_logging" "main" {
  count = var.enable_logging ? 1 : 0

  bucket        = aws_s3_bucket.main.id
  target_bucket = aws_s3_bucket.logs[0].id
  target_prefix = "access-logs/"
}

# Block public access on logs bucket too
resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
