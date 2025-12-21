# =============================================================================
# 反模式示例：硬编码的密钥
# Anti-Pattern: Hardcoded Secrets
# =============================================================================
#
# ❌ 不要这样做！这个文件展示了常见的安全错误。
# ❌ DO NOT do this! This file demonstrates common security mistakes.
#
# 问题：
# 1. 数据库密码直接写在代码中 → Git 历史中永远存在
# 2. API 密钥硬编码 → 任何能访问代码的人都能看到
# 3. 即使使用 sensitive = true，State 文件中仍是明文
#
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

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
      Warning     = "anti-pattern-demo"
    }
  }
}

# =============================================================================
# ❌ 问题 1：硬编码数据库密码
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = "myapp-db-${var.environment}"

  # 数据库配置
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp2"
  db_name              = "myapp"
  skip_final_snapshot  = true

  # ❌ 硬编码的凭证 - 严重安全问题！
  # 这些值会：
  # - 出现在 Git 历史中
  # - 出现在 terraform.tfstate 中（明文）
  # - 在 PR 中对所有人可见
  username = "admin"
  password = "SuperSecret123!"  # tfsec:ignore:general-secrets-sensitive-in-local

  # 网络配置
  publicly_accessible    = false  # 至少这个做对了
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "myapp-db-${var.environment}"
  }
}

# =============================================================================
# ❌ 问题 2：硬编码 API 密钥
# =============================================================================

resource "aws_ssm_parameter" "api_key" {
  name        = "/myapp/${var.environment}/api_key"
  type        = "String"  # ❌ 应该用 SecureString
  value       = "sk_live_abc123xyz789"  # ❌ 硬编码的 API 密钥！
  description = "Third-party API key"

  tags = {
    Name = "api-key-${var.environment}"
  }
}

# =============================================================================
# ❌ 问题 3：sensitive = true 的误解
# =============================================================================

# 很多人以为这样就安全了，但并不是！
variable "another_secret" {
  type        = string
  description = "Another secret value"
  default     = "AnotherHardcodedSecret"  # ❌ 默认值是硬编码的
  sensitive   = true  # ⚠️ 只是屏蔽 CLI 输出，State 中仍是明文！
}

resource "aws_ssm_parameter" "another_secret" {
  name        = "/myapp/${var.environment}/another_secret"
  type        = "SecureString"
  value       = var.another_secret
  description = "This value is still visible in tfstate!"

  tags = {
    Name = "another-secret-${var.environment}"
  }
}

# =============================================================================
# 支撑资源（这些是正确的）
# =============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "myapp-db-subnet-${var.environment}"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "myapp-db-subnet-${var.environment}"
  }
}

resource "aws_security_group" "db" {
  name        = "myapp-db-sg-${var.environment}"
  description = "Security group for RDS instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # 内网访问
    description = "MySQL from internal network"
  }

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
}
