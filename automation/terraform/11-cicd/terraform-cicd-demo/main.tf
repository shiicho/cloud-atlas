# main.tf
# Demo resources for CI/CD pipeline testing
#
# This creates a simple S3 bucket. When you modify this file:
# 1. Create a PR -> GitHub Actions runs `terraform plan`
# 2. Merge PR -> GitHub Actions runs `terraform apply`
#
# Try adding your own tag in the tags block to test the pipeline!

# =============================================================================
# Random suffix for unique bucket name
# =============================================================================
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# S3 Bucket - Demo resource
# =============================================================================
resource "aws_s3_bucket" "demo" {
  bucket = "cicd-demo-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "CI/CD Demo Bucket"
    Environment = var.environment
    # TODO: Add your own tag here to test the CI/CD pipeline!
    # Example: MyName = "your-name"
  }
}

# =============================================================================
# Versioning (production best practice)
# =============================================================================
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# Block public access (security best practice)
# =============================================================================
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Encryption (security best practice)
# =============================================================================
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
