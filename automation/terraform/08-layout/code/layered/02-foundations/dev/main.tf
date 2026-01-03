# =============================================================================
# Foundations Layer - 数据存储基础设施
# =============================================================================
# 第二层：数据库、缓存、存储
# 变更频率中等，依赖网络层
# =============================================================================

# -----------------------------------------------------------------------------
# 本地变量
# -----------------------------------------------------------------------------
locals {
  environment = "dev"
  name_prefix = "demo-${local.environment}"

  # 从 Network Layer 获取数据
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

# -----------------------------------------------------------------------------
# 随机后缀
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket（数据存储）
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "data" {
  bucket = "${local.name_prefix}-data-${random_id.suffix.hex}"

  force_destroy = true  # dev 环境允许强制删除

  tags = {
    Name    = "${local.name_prefix}-data"
    Purpose = "Application data storage"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# Security Group for Data Layer
# -----------------------------------------------------------------------------
resource "aws_security_group" "data" {
  name        = "${local.name_prefix}-data-sg"
  description = "Security group for data layer resources"
  vpc_id      = local.vpc_id

  # 允许来自 VPC 内部的访问
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
    description = "Allow all from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-data-sg"
  }
}

# -----------------------------------------------------------------------------
# DB Subnet Group（为将来的 RDS 准备）
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}
