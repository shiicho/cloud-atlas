# main.tf
# Drift 检测演练 - EC2 实例
# =============================================================================
#
# 本文件创建一个简单的 EC2 实例，用于演练 Drift 检测和修复。
#
# 使用场景:
#   1. terraform apply 创建资源
#   2. 使用 drift-inject.sh 脚本修改标签（模拟 Console 操作）
#   3. terraform plan 检测 Drift
#   4. terraform apply 修复 Drift
#
# =============================================================================

# -----------------------------------------------------------------------------
# Data Source: 获取最新的 Amazon Linux 2023 AMI
# -----------------------------------------------------------------------------
# 使用 data source 动态查询 AMI，避免硬编码 AMI ID。
# 这样在不同区域或 AMI 更新后代码仍然有效。

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Data Source: 获取默认 VPC
# -----------------------------------------------------------------------------
# 使用默认 VPC 简化演示。
# 生产环境应使用自定义 VPC。

data "aws_vpc" "default" {
  default = true
}

# -----------------------------------------------------------------------------
# Data Source: 获取默认子网
# -----------------------------------------------------------------------------

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# Security Group: 允许 SSM 访问
# -----------------------------------------------------------------------------
# 只允许 SSM Session Manager 访问，无需开放 SSH 端口。

resource "aws_security_group" "demo" {
  name        = "${var.instance_name}-sg"
  description = "Security group for drift detection demo"
  vpc_id      = data.aws_vpc.default.id

  # 出站规则：允许所有出站流量（SSM Agent 需要）
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.instance_name}-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# IAM Role: SSM 访问权限
# -----------------------------------------------------------------------------

resource "aws_iam_role" "demo" {
  name = "${var.instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.instance_name}-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.demo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "demo" {
  name = "${var.instance_name}-profile"
  role = aws_iam_role.demo.name
}

# -----------------------------------------------------------------------------
# EC2 Instance: 演示用实例
# -----------------------------------------------------------------------------
# 这是 Drift 检测的主要目标资源。
# 我们会用脚本修改它的标签，然后用 Terraform 检测和修复。

resource "aws_instance" "demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.demo.id]
  iam_instance_profile   = aws_iam_instance_profile.demo.name

  # 重要：这些标签会被 drift-inject.sh 修改
  # 用于演示 Drift 检测
  tags = {
    Name        = var.instance_name
    Environment = var.environment    # 会被改成 "production"
    Owner       = var.owner          # 会被删除
    # ModifiedBy, ModifiedAt, Reason 会被添加
  }

  # 防止意外删除
  # 演示时可以注释掉这行
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# -----------------------------------------------------------------------------
# 注释：Drift 的常见来源
# -----------------------------------------------------------------------------
#
# 1. 标签修改（本演示重点）
#    - 有人在 Console 添加/修改/删除标签
#    - 最常见，也最容易检测
#
# 2. 安全组规则
#    - 紧急开放端口后忘记关闭
#    - 添加临时入站规则
#
# 3. 实例类型变更
#    - 紧急扩容后忘记更新代码
#    - 需要 stop/start，影响较大
#
# 4. IAM 策略修改
#    - 添加临时权限后忘记删除
#    - 安全风险较高
#
# -----------------------------------------------------------------------------
