# =============================================================================
# 最佳实践示例：动态获取密钥
# Best Practice: Dynamic Secret Retrieval
# =============================================================================
#
# ✓ 从 SSM Parameter Store 动态获取密钥
# ✓ 密钥由安全团队单独管理，Terraform 代码中不包含任何密钥值
# ✓ 使用 KMS 加密的 SecureString 参数
# ✓ 通过 IAM 控制谁可以访问哪些密钥
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
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "security-demo"
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# 从 SSM Parameter Store 获取密钥
# =============================================================================

# 数据库密码 - 由安全团队预先存储在 SSM 中
data "aws_ssm_parameter" "db_password" {
  name            = "/myapp/${var.environment}/db/password"
  with_decryption = true  # 自动解密 SecureString
}

# API 密钥 - 同样从 SSM 获取
data "aws_ssm_parameter" "api_key" {
  name            = "/myapp/${var.environment}/api_key"
  with_decryption = true
}

# 可选：从 Secrets Manager 获取（适用于需要自动轮换的场景）
# data "aws_secretsmanager_secret_version" "db_creds" {
#   secret_id = "myapp/${var.environment}/db-credentials"
# }
#
# locals {
#   db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)
# }

# =============================================================================
# 使用动态获取的密钥创建资源
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = "myapp-db-${var.environment}"

  # 数据库配置
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  storage_type         = "gp2"
  db_name              = "myapp"
  skip_final_snapshot  = var.environment != "prod"  # 生产环境保留快照

  # ✓ 从 SSM 动态获取的凭证
  # 代码中没有任何敏感值
  username = var.db_username
  password = data.aws_ssm_parameter.db_password.value

  # ✓ 安全的网络配置
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  # ✓ 启用加密
  storage_encrypted = true
  kms_key_id        = var.db_kms_key_id  # 可选：使用客户管理的 KMS 密钥

  # ✓ 启用性能洞察
  performance_insights_enabled = var.environment == "prod"

  # ✓ 启用自动备份（生产环境）
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # ✓ 启用删除保护（生产环境）
  deletion_protection = var.environment == "prod"

  tags = {
    Name = "myapp-db-${var.environment}"
  }
}

# =============================================================================
# 支撑资源
# =============================================================================

data "aws_vpc" "selected" {
  id = var.vpc_id != "" ? var.vpc_id : null

  dynamic "filter" {
    for_each = var.vpc_id == "" ? [1] : []
    content {
      name   = "isDefault"
      values = ["true"]
    }
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  # 如果有标签，筛选私有子网
  dynamic "filter" {
    for_each = var.use_private_subnets ? [1] : []
    content {
      name   = "tag:Tier"
      values = ["private"]
    }
  }
}

resource "aws_db_subnet_group" "main" {
  name        = "myapp-db-subnet-${var.environment}"
  description = "Database subnet group for ${var.environment}"
  subnet_ids  = data.aws_subnets.private.ids

  tags = {
    Name = "myapp-db-subnet-${var.environment}"
  }
}

resource "aws_security_group" "db" {
  name        = "myapp-db-sg-${var.environment}"
  description = "Security group for RDS instance"
  vpc_id      = data.aws_vpc.selected.id

  # ✓ 限制来源 IP 范围
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = var.allowed_db_cidr_blocks
    description     = "MySQL from allowed networks"
  }

  # ✓ 显式拒绝其他入站流量（Security Group 默认行为）

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "myapp-db-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}
